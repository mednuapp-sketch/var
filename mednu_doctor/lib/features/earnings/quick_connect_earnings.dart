import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// A uniform, read-only "earning row" so appointment docs and quick-connect
/// consultation docs can be aggregated by the same analytics code. Mirrors the
/// subset of an `appointments` doc the Earnings UI reads (status, fee, date,
/// time, patientName, consultationType, createdAt, patientId).
class EarningEntry {
  final String id;
  final Map<String, dynamic> _data;
  const EarningEntry(this.id, this._data);

  factory EarningEntry.fromDoc(
          QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      EarningEntry(doc.id, doc.data());

  Map<String, dynamic> data() => _data;
}

/// Completed quick-connect (instant) consultations, as earning entries.
///
/// A scheduled appointment's consultation doc carries an `appointmentId` and is
/// already counted through its `appointments` doc, so those are skipped, as are
/// provider-initiated calls (callerType != 'patient') and docs with no fee.
class QuickConnectEarnings {
  QuickConnectEarnings._();

  static Stream<List<EarningEntry>> stream(String uid) => FirebaseFirestore
      .instance
      .collection('consultations')
      .where('doctorId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final out = <EarningEntry>[];
        for (final doc in snap.docs) {
          final e = _normalize(doc.id, doc.data());
          if (e != null) out.add(e);
        }
        return out;
      });

  static EarningEntry? _normalize(String id, Map<String, dynamic> d) {
    if (d['callerType'] != 'patient') return null;
    final status = d['status'];
    if (status != 'ended' && status != 'completed') return null;
    final appointmentId = d['appointmentId'];
    if (appointmentId is String && appointmentId.isNotEmpty) return null;
    final fee = d['fee'];
    final amount = fee is num ? fee : num.tryParse('${fee ?? ''}');
    if (amount == null || amount <= 0) return null;

    final ts = (d['endedAt'] as Timestamp?) ??
        (d['updatedAt'] as Timestamp?) ??
        (d['createdAt'] as Timestamp?);
    final dt = ts?.toDate() ?? DateTime.now();
    return EarningEntry(id, {
      'status': 'completed',
      'fee': amount,
      'date': DateFormat('yyyy-MM-dd').format(dt),
      'time': DateFormat('hh:mm a').format(dt),
      'patientName': d['patientName'] ?? 'Patient',
      'patientId': d['patientId'] ?? '',
      'consultationType': d['consultationType'] ?? 'Video',
      'createdAt': ts ?? Timestamp.fromDate(dt),
      'source': 'quick_connect',
    });
  }
}

/// Subscribes once (stable across parent rebuilds) and hands the current
/// quick-connect entries to [builder]. Until the first snapshot arrives — or if
/// the query fails — the list is empty, so appointment earnings still render.
class QuickConnectEarningsBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext context, List<EarningEntry> entries)
      builder;
  const QuickConnectEarningsBuilder(
      {super.key, required this.uid, required this.builder});

  @override
  State<QuickConnectEarningsBuilder> createState() =>
      _QuickConnectEarningsBuilderState();
}

class _QuickConnectEarningsBuilderState
    extends State<QuickConnectEarningsBuilder> {
  late Stream<List<EarningEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = QuickConnectEarnings.stream(widget.uid);
  }

  @override
  void didUpdateWidget(covariant QuickConnectEarningsBuilder old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _stream = QuickConnectEarnings.stream(widget.uid);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<EarningEntry>>(
        stream: _stream,
        builder: (context, snap) =>
            widget.builder(context, snap.hasError ? const [] : (snap.data ?? const [])),
      );
}
