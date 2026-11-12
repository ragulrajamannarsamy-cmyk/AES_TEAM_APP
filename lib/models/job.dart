import 'package:cloud_firestore/cloud_firestore.dart';

import 'requests.dart';

enum JobStatus { planned, inProgress, done }

const jobStatusLabels = {
  JobStatus.planned: 'Planned',
  JobStatus.inProgress: 'In progress',
  JobStatus.done: 'Done',
};

const workTypes = [
  'Transformer repair',
  'Transformer maintenance',
  'Erection / commissioning',
  'Testing',
  'Breakdown',
  'Other',
];

class Job {
  final String id;
  final String title;
  final String siteName;
  final String workType;
  final List<String> assigned; // phones
  final Map<String, String> assignedNames; // phone -> name
  final DateTime? startDate;
  final DateTime? endDate;
  final JobStatus status;
  final String notes;

  const Job({
    required this.id,
    required this.title,
    required this.siteName,
    required this.workType,
    required this.assigned,
    required this.assignedNames,
    required this.status,
    required this.notes,
    this.startDate,
    this.endDate,
  });

  factory Job.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Job(
      id: d.id,
      title: (m['title'] ?? '') as String,
      siteName: (m['siteName'] ?? '') as String,
      workType: (m['workType'] ?? '') as String,
      assigned: List<String>.from((m['assigned'] ?? const []) as List),
      assignedNames:
          Map<String, String>.from((m['assignedNames'] ?? const {}) as Map),
      startDate: tsDate(m['startDate']),
      endDate: tsDate(m['endDate']),
      status: JobStatus.values.firstWhere((s) => s.name == m['status'],
          orElse: () => JobStatus.planned),
      notes: (m['notes'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'siteName': siteName,
        'workType': workType,
        'assigned': assigned,
        'assignedNames': assignedNames,
        'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
        'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
        'status': status.name,
        'notes': notes,
      };
}

/// Progress note + photo posted on a job by a worker or admin.
class JobUpdate {
  final String phone;
  final String name;
  final String text;
  final String? photoUrl;
  final DateTime? time;

  const JobUpdate({
    required this.phone,
    required this.name,
    required this.text,
    this.photoUrl,
    this.time,
  });

  factory JobUpdate.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return JobUpdate(
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      photoUrl: m['photoUrl'] as String?,
      time: tsDate(m['time']),
    );
  }
}
