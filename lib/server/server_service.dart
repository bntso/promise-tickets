import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../qr/payload.dart';

const String kUsernameKey = 'username';
const String kAcceptedTicketsKey = 'acceptedServerTickets';

final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// A user found in the server directory.
class DirectoryEntry {
  const DirectoryEntry({
    required this.username,
    required this.displayName,
    required this.publicKeyHex,
    required this.uid,
  });

  final String username;
  final String displayName;
  final String publicKeyHex;
  final String uid;
}

/// A ticket document as stored in Firestore (`tickets/{ticketId}`). The
/// [gift] map is the full signed PT2 gift payload; the server is an
/// untrusted relay, so clients still verify its signature before use.
class ServerTicket {
  ServerTicket({
    required this.id,
    required this.gift,
    required this.fromUid,
    required this.fromUsername,
    required this.fromPubKey,
    required this.toUid,
    required this.toUsername,
    required this.status,
    this.receipt,
  });

  factory ServerTicket.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ServerTicket(
      id: doc.id,
      gift: Map<String, dynamic>.from(data['gift'] as Map? ?? const {}),
      fromUid: data['fromUid'] as String? ?? '',
      fromUsername: data['fromUsername'] as String? ?? '',
      fromPubKey: data['fromPubKey'] as String? ?? '',
      toUid: data['toUid'] as String? ?? '',
      toUsername: data['toUsername'] as String? ?? '',
      status: data['status'] as String? ?? 'offered',
      receipt: data['receipt'] is Map
          ? Map<String, dynamic>.from(data['receipt'] as Map)
          : null,
    );
  }

  final String id;
  final Map<String, dynamic> gift;
  final String fromUid;
  final String fromUsername;
  final String fromPubKey;
  final String toUid;
  final String toUsername;
  final String status;
  final Map<String, dynamic>? receipt;
}

/// Firebase backend: anonymous auth, the username directory, and the ticket
/// relay. Constructed in degraded (offline-only) mode when Firebase init or
/// sign-in failed — every v1.1 feature keeps working and all server calls
/// report unavailability.
class ServerService extends ChangeNotifier {
  ServerService({
    this._auth,
    this._firestore,
    required this._settings,
  });

  /// Offline-only mode: no auth, no Firestore, all server UI hidden.
  ServerService.offline({required Box settings}) : this(settings: settings);

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final Box _settings;

  String? get uid => _auth?.currentUser?.uid;

  /// False in degraded mode (Firebase unavailable / signed out).
  bool get available => _auth != null && _firestore != null && uid != null;

  String? get username {
    final value = _settings.get(kUsernameKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  bool get isRegistered => available && username != null;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore!.collection('users');

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _firestore!.collection('tickets');

  // -------------------------------------------------------------------------
  // Registration & directory
  // -------------------------------------------------------------------------

  static String? validateUsername(String username) {
    if (!_usernamePattern.hasMatch(username)) {
      return '3–20 characters: lowercase letters, digits, underscores.';
    }
    return null;
  }

  Future<bool> isUsernameAvailable(String username) async {
    _requireAvailable();
    final doc = await _users.doc(username).get();
    return !doc.exists;
  }

  /// Claims [username] in a transaction; the first claimant wins.
  Future<void> register(String username, Identity identity) async {
    _requireAvailable();
    final error = validateUsername(username);
    if (error != null) throw FormatException(error);
    final ref = _users.doc(username);
    await _firestore!.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        throw const FormatException('That username is taken.');
      }
      transaction.set(ref, {
        'displayName': identity.name,
        'publicKey': identity.publicKeyHex,
        'uid': uid,
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    await _settings.put(kUsernameKey, username);
    notifyListeners();
  }

  /// Exact username lookup in the directory.
  Future<DirectoryEntry?> lookupUser(String username) async {
    _requireAvailable();
    final doc = await _users.doc(username.trim().toLowerCase()).get();
    final data = doc.data();
    if (data == null) return null;
    return DirectoryEntry(
      username: doc.id,
      displayName: data['displayName'] as String? ?? doc.id,
      publicKeyHex: data['publicKey'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
    );
  }

  // -------------------------------------------------------------------------
  // Remote gifts
  // -------------------------------------------------------------------------

  /// Signs the PT2 gift payload and publishes it to `tickets/{ticket.id}`
  /// with status 'offered', exactly matching the deployed security rules.
  Future<void> publishGift(
    Ticket ticket,
    Identity identity, {
    required String toUid,
    required String toUsername,
  }) async {
    _requireRegistered();
    final gift = await encodeGiftV2Map(ticket, identity);
    await _tickets.doc(ticket.id).set({
      'gift': gift,
      'fromUid': uid,
      'fromUsername': username,
      'fromPubKey': identity.publicKeyHex,
      'toUid': toUid,
      'toUsername': toUsername,
      'status': 'offered',
      'createdAt': ticket.createdAt.toIso8601String(),
      'expiresAt': ticket.expiresAt.toIso8601String(),
    });
  }

  /// Incoming gifts waiting for me to accept.
  Stream<List<ServerTicket>> watchInbox() {
    return _tickets
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ServerTicket.fromDoc).toList());
  }

  /// All server tickets I sent (for status reconciliation).
  Stream<List<ServerTicket>> watchOutgoing() {
    return _tickets
        .where('fromUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ServerTicket.fromDoc).toList());
  }

  /// All server tickets addressed to me (for status reconciliation).
  Stream<List<ServerTicket>> watchIncoming() {
    return _tickets
        .where('toUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(ServerTicket.fromDoc).toList());
  }

  // -------------------------------------------------------------------------
  // Claim & fulfill
  // -------------------------------------------------------------------------

  /// Holder side: offered → claimRequested.
  Future<void> requestClaim(String ticketId) async {
    _requireAvailable();
    await _tickets.doc(ticketId).update({'status': 'claimRequested'});
  }

  /// Giver side: signs a fulfillment receipt and marks the server doc
  /// fulfilled (allowed from both 'offered' and 'claimRequested').
  Future<void> fulfill(String ticketId, Ticket ticket, Identity identity) async {
    _requireAvailable();
    final receipt = await encodeReceipt(ticket, identity);
    await _tickets.doc(ticketId).update({
      'status': 'fulfilled',
      'receipt': receipt,
    });
  }

  /// In-person shortcut after a QR claim was confirmed locally: if a server
  /// doc exists for this ticket, write fulfilled + receipt there too.
  /// Missing docs and offline errors are swallowed — the local redemption
  /// already succeeded.
  Future<void> fulfillIfExists(Ticket ticket, Identity identity) async {
    if (!available) return;
    try {
      final doc = await _tickets.doc(ticket.id).get();
      if (!doc.exists) return;
      final status = doc.data()?['status'];
      if (status != 'offered' && status != 'claimRequested') return;
      await fulfill(ticket.id, ticket, identity);
    } catch (_) {
      // Best-effort only.
    }
  }

  // -------------------------------------------------------------------------
  // Accepted inbox items (hidden from the inbox once imported locally)
  // -------------------------------------------------------------------------

  bool isAccepted(String ticketId) => _acceptedIds().contains(ticketId);

  Future<void> markAccepted(String ticketId) async {
    final ids = _acceptedIds()..add(ticketId);
    await _settings.put(kAcceptedTicketsKey, ids.toList());
    notifyListeners();
  }

  Set<String> _acceptedIds() {
    final stored = _settings.get(kAcceptedTicketsKey);
    if (stored is List) {
      return stored.whereType<String>().toSet();
    }
    return <String>{};
  }

  void _requireAvailable() {
    if (!available) {
      throw StateError('The server is not available right now.');
    }
  }

  void _requireRegistered() {
    if (!isRegistered) {
      throw StateError('Pick a username first.');
    }
  }
}
