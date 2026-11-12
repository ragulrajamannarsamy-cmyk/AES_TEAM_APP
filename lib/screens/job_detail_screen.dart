import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/job.dart';
import '../services/job_service.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'admin/jobs_admin.dart';

Color jobColor(JobStatus s) => switch (s) {
      JobStatus.planned => kAmber,
      JobStatus.inProgress => kNavy,
      JobStatus.done => kGreen,
    };

/// Shown on the Attendance tab: the worker's open jobs.
class MyJobsList extends StatelessWidget {
  final AppUser me;
  const MyJobsList({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Job>>(
      stream: JobService.watchMine(me.phone),
      builder: (context, snap) {
        final jobs =
            (snap.data ?? []).where((j) => j.status != JobStatus.done).toList();
        if (jobs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text('My jobs', style: Theme.of(context).textTheme.titleMedium),
            for (final j in jobs) JobTile(job: j, me: me),
          ],
        );
      },
    );
  }
}

class JobTile extends StatelessWidget {
  final Job job;
  final AppUser me;
  const JobTile({super.key, required this.job, required this.me});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(job.title),
          subtitle: Text([
            job.siteName,
            job.workType,
            if (job.startDate != null) shortDate.format(job.startDate!),
            '${job.assigned.length} people',
          ].where((s) => s.isNotEmpty).join(' · ')),
          trailing: StatusChip(
              jobStatusLabels[job.status]!.toUpperCase(), jobColor(job.status)),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => JobDetailScreen(jobId: job.id, me: me))),
        ),
      );
}

class JobDetailScreen extends StatelessWidget {
  final String jobId;
  final AppUser me;
  const JobDetailScreen({super.key, required this.jobId, required this.me});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Job?>(
      stream: JobService.watch(jobId),
      builder: (context, snap) {
        final j = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(j?.title ?? 'Job'),
            actions: [
              if (j != null && me.isAdmin)
                IconButton(
                  tooltip: 'Edit job',
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => JobFormScreen(job: j))),
                ),
            ],
          ),
          floatingActionButton: j == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _post(context),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Post update'),
                ),
          body: j == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    KV('Site', j.siteName),
                    KV('Work', j.workType),
                    if (j.startDate != null)
                      KV('Dates',
                          '${shortDate.format(j.startDate!)}${j.endDate == null ? '' : ' – ${shortDate.format(j.endDate!)}'}'),
                    KV('Team', j.assignedNames.values.join(', ')),
                    if (j.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(j.notes),
                    ],
                    const SizedBox(height: 12),
                    SegmentedButton<JobStatus>(
                      segments: [
                        for (final s in JobStatus.values)
                          ButtonSegment(
                              value: s, label: Text(jobStatusLabels[s]!)),
                      ],
                      selected: {j.status},
                      onSelectionChanged: (v) =>
                          JobService.setStatus(j.id, v.first),
                    ),
                    const SizedBox(height: 16),
                    Text('Updates',
                        style: Theme.of(context).textTheme.titleMedium),
                    StreamBuilder<List<JobUpdate>>(
                      stream: JobService.watchUpdates(j.id),
                      builder: (context, us) {
                        final ups = us.data ?? [];
                        if (ups.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('No updates yet.'),
                          );
                        }
                        return Column(children: [
                          for (final u in ups)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${u.name} · ${u.time == null ? 'now' : '${shortDate.format(u.time!)} ${timeFmt.format(u.time!)}'}',
                                        style: const TextStyle(
                                            color: Colors.black54)),
                                    if (u.text.isNotEmpty) Text(u.text),
                                    if (u.photoUrl != null) ...[
                                      const SizedBox(height: 6),
                                      GestureDetector(
                                        onTap: () => openUrl(u.photoUrl!),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(u.photoUrl!,
                                              height: 200,
                                              width: double.infinity,
                                              fit: BoxFit.cover),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ]);
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _post(BuildContext context) async {
    File? photo = await takePhoto();
    if (!context.mounted) return;
    final text = await askNote(
        context, photo == null ? 'Update (no photo)' : 'Add a note to the photo',
        action: 'Post');
    if (text == null) return;
    if (photo == null && text.isEmpty) return;
    await JobService.postUpdate(
        jobId: jobId, phone: me.phone, name: me.name, text: text, photo: photo);
    if (context.mounted) toast(context, 'Update posted');
  }
}
