import 'dart:async';

import 'package:flutter/foundation.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../qr/payload.dart';
import '../state/ticket_store.dart';
import 'server_service.dart';

/// Keeps the local wallet in sync with the server: listens to the ticket
/// docs where I'm the giver or the recipient, reconciles their status into
/// the local Hive store (verifying receipt signatures), and exposes the
/// inbox and pending-claims lists for the wallet UI. Listeners only run
/// while registered; everything is torn down on dispose.
class ServerSync extends ChangeNotifier {
  ServerSync({required this._service}) {
    _service.addListener(_onServiceChanged);
  }

  final ServerService _service;

  TicketStore? _tickets;
  Identity? _identity;

  StreamSubscription<List<ServerTicket>>? _inboxSub;
  StreamSubscription<List<ServerTicket>>? _outgoingSub;
  StreamSubscription<List<ServerTicket>>? _incomingSub;

  List<ServerTicket> _inboxDocs = const [];
  List<ServerTicket> _outgoing = const [];

  /// Offered gifts addressed to me that I haven't accepted yet.
  List<ServerTicket> get inbox {
    final tickets = _tickets;
    return _inboxDocs
        .where((doc) =>
            !_service.isAccepted(doc.id) &&
            (tickets == null || tickets.byId(doc.id) == null))
        .toList();
  }

  /// Tickets I sent whose holder is asking to claim.
  List<ServerTicket> get pendingClaims =>
      _outgoing.where((doc) => doc.status == 'claimRequested').toList();

  /// (Re)binds the app-level stores. Called by the ProxyProvider whenever
  /// any dependency changes; starts or stops the listeners to match the
  /// registration state.
  void attach({
    required TicketStore tickets,
    required Identity identity,
  }) {
    _tickets = tickets;
    _identity = identity;
    _syncListeners();
  }

  void _onServiceChanged() {
    _syncListeners();
    notifyListeners();
  }

  void _syncListeners() {
    final shouldListen = _service.isRegistered && _tickets != null;
    if (shouldListen && _inboxSub == null) {
      _inboxSub = _service.watchInbox().listen(
        (docs) {
          _inboxDocs = docs;
          notifyListeners();
        },
        onError: (_) {},
      );
      _outgoingSub = _service.watchOutgoing().listen(
        (docs) {
          _outgoing = docs;
          _reconcile(docs);
          notifyListeners();
        },
        onError: (_) {},
      );
      _incomingSub = _service.watchIncoming().listen(
        (docs) {
          _reconcile(docs);
        },
        onError: (_) {},
      );
    } else if (!shouldListen && _inboxSub != null) {
      _cancelListeners();
      _inboxDocs = const [];
      _outgoing = const [];
    }
  }

  /// Reconciles server docs into the local store by ticket id: verified
  /// fulfillments become redeemed (with the receipt date), other statuses
  /// update the server chip. Tampered receipts are ignored.
  Future<void> _reconcile(List<ServerTicket> docs) async {
    final tickets = _tickets;
    if (tickets == null) return;
    for (final doc in docs) {
      final local = tickets.byId(doc.id);
      if (local == null) continue;
      if (doc.status == 'fulfilled') {
        final receipt = doc.receipt;
        if (receipt == null) continue;
        if (!await verifyReceipt(receipt, local)) continue;
        final fulfilledAt = DateTime.parse(receipt['fulfilledAt'] as String);
        await tickets.markFulfilled(doc.id, fulfilledAt);
      } else {
        final status = ServerTicketStatus.values.asNameMap()[doc.status];
        if (status != null) await tickets.markServerStatus(doc.id, status);
      }
    }
  }

  /// Accepts an inbox gift: verifies and imports it locally as holder, then
  /// hides it from the inbox. The server doc stays 'offered' until claimed.
  Future<Ticket> accept(ServerTicket doc) async {
    final tickets = _tickets;
    final identity = _identity;
    if (tickets == null || identity == null) {
      throw StateError('Not ready yet.');
    }
    final held = await tickets.importGiftMap(
      doc.gift,
      holderName: identity.name,
      holderPubKey: identity.publicKeyHex,
      serverStatus: ServerTicketStatus.offered,
    );
    await _service.markAccepted(doc.id);
    notifyListeners();
    return held;
  }

  void _cancelListeners() {
    _inboxSub?.cancel();
    _outgoingSub?.cancel();
    _incomingSub?.cancel();
    _inboxSub = null;
    _outgoingSub = null;
    _incomingSub = null;
  }

  @override
  void dispose() {
    _cancelListeners();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
