import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/job.dart';
import '../../models/site.dart';
import '../../services/job_service.dart';
import '../../services/site_service.dart';
import '../../services/user_service.dart';
import '../../util.dart';
import '../../widgets/common.dart';
import '../job_detail_screen.dart';

/// Create jobs per substation, assign the team, track status.
class JobsAdmin extends StatefulWidget {
  final AppUser me;
  const JobsAdmin({super.key, required this.me});

  @override
  State<JobsAdmin> createState() => _JobsAdminState();
}

class _JobsAdminState extends State<JobsAdmin> {
  JobStatus? _filter; // null = open (planned + in progress)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newJob',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const JobFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New job'),
      ),
      body: StreamBuilder<List<Job>>(
        stream: JobService.watchAll(),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final jobs = _filter == null
              ? all.where((j) => j.status != JobStatus.done).toList()
              : all.where((j) => j.status == _filter).toList();
          int count(JobStatus s) => all.where((j) => j.status == s).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: Text(
                      'Open (${count(JobStatus.planned) + count(JobStatus.inProgress)})'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final s in JobStatus.values)
                  ChoiceChip(
                    label: Text('${jobStatusLabels[s]} (${count(s)})'),
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                  ),
              ]),
              const SizedBox(height: 8),
              if (jobs.isEmpty)
                const EmptyState('No jobs here. Tap "New job" to create one.')
              else
                for (final j in jobs) JobTile(job: j, me: widget.me),
              if (all.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => shareCsv('jobs.csv', [
                    ['Job', 'Site', 'Work type', 'Status', 'Start', 'End',
                      'Team', 'Notes'],
                    for (final j in all)
                      [
                        j.title,
                        j.siteName,
                        j.workType,
                        jobStatusLabels[j.status],
                        j.startDate == null ? '' : dayFmt.format(j.startDate!),
                        j.endDate == null ? '' : dayFmt.format(j.endDate!),
                        j.assignedNames.values.join('; '),
                        j.notes,
                      ],
                  ]),
                  icon: const Icon(Icons.download),
                  label: const Text('Export all jobs'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class JobFormScreen extends StatefulWidget {
  final Job? job;
  const JobFormScreen({super.key, this.job});

  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  late final _title = TextEditingController(text: widget.job?.title ?? '');
  late final _notes = TextEditingController(text: widget.job?.notes ?? '');
  late String _site = widget.job?.siteName ?? '';
  late String _type = widget.job?.workType ?? workTypes.first;
  late DateTime? _start = widget.job?.startDate ?? DateTime.now();
  late DateTime? _end = widget.job?.endDate;
  late JobStatus _status = widget.job?.status ?? JobStatus.planned;
  late final Map<String, String> _team =
      Map.of(widget.job?.assignedNames ?? const {});
  bool _busy = false;

  Future<void> _pickTeam(List<AppUser> staff) async {
    final picked = Map.of(_team);
    var q = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final list = staff
              .where((u) => u.name.toLowerCase().contains(q.toLowerCase()))
              .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (_, ctrl) => Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: 'Search (${picked.length} selected)',
                      isDense: true),
                  onChanged: (v) => setS(() => q = v),
                ),
              ),
              Expanded(
                child: ListView(controller: ctrl, children: [
                  for (final u in list)
                    CheckboxListTile(
                      value: picked.containsKey(u.phone),
                      title: Text(u.name),
                      subtitle: Text(roleLabels[u.role]!),
                      onChanged: (v) => setS(() => v == true
                          ? picked[u.phone] = u.name
                          : picked.remove(u.phone)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ),
            ]),
          );
        },
      ),
    );
    setState(() {
      _team
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _site.isEmpty) {
      toast(context, 'Enter job title and choose a site.', error: true);
      return;
    }
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      toast(context, 'End date is before start date.', error: true);
      return;
    }
    setState(() => _busy = true);
    await JobService.save(Job(
      id: widget.job?.id ?? '',
      title: _title.text.trim(),
      siteName: _site,
      workType: _type,
      assigned: _team.keys.toList(),
      assignedNames: _team,
      startDate: _start,
      endDate: _end,
      status: _status,
      notes: _notes.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final note = await askNote(context, 'Delete this job?', action: 'Delete');
    if (note == null || widget.job == null) return;
    await JobService.delete(widget.job!.id);
    // Close the edit screen and the job's detail screen.
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<DateTime?> _date(DateTime? init) => showDatePicker(
        context: context,
        initialDate: init ?? DateTime.now(),
        firstDate: DateTime(2025),
        lastDate: DateTime(2030),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.job == null ? 'New job' : 'Edit job'),
        actions: [
          if (widget.job != null)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete)),
        ],
      ),
      body: StreamBuilder<List<Site>>(
        stream: SiteService.watchAll(),
        builder: (context, siteSnap) {
          final sites = siteSnap.data ?? [];
          final siteNames = {
            for (final s in sites) s.name,
            if (_site.isNotEmpty) _site,
          }.toList();
          return StreamBuilder<List<AppUser>>(
            stream: UserService.watchAll(),
            builder: (context, userSnap) {
              final staff = (userSnap.data ?? [])
                  .where((u) => u.active && !u.isAdmin)
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                        labelText: 'Job title',
                        hintText: 'e.g. 100 kVA transformer oil filtration'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _site.isEmpty ? null : _site,
                    decoration: const InputDecoration(labelText: 'Site'),
                    items: [
                      for (final n in siteNames)
                        DropdownMenuItem(value: n, child: Text(n)),
                    ],
                    onChanged: (v) => setState(() => _site = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: workTypes.contains(_type) ? _type : workTypes.last,
                    decoration: const InputDecoration(labelText: 'Work type'),
                    items: [
                      for (final t in workTypes)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await _date(_start);
                          if (d != null) setState(() => _start = d);
                        },
                        child: Text(_start == null
                            ? 'Start date'
                            : 'Start ${shortDate.format(_start!)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await _date(_end ?? _start);
                          if (d != null) setState(() => _end = d);
                        },
                        child: Text(_end == null
                            ? 'End date'
                            : 'End ${shortDate.format(_end!)}'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SegmentedButton<JobStatus>(
                    segments: [
                      for (final s in JobStatus.values)
                        ButtonSegment(
                            value: s, label: Text(jobStatusLabels[s]!)),
                    ],
                    selected: {_status},
                    onSelectionChanged: (v) =>
                        setState(() => _status = v.first),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups),
                    title: Text('Team (${_team.length})'),
                    subtitle: Text(_team.isEmpty
                        ? 'Nobody assigned'
                        : _team.values.join(', ')),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _pickTeam(staff),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Saving…' : 'Save job'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
