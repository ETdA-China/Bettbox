import 'dart:async';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/pages/toolbox/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _refreshInterval = Duration(seconds: 2);

String formatEasytierBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String easytierStateLabel(String state) => switch (state) {
  'running' => '运行中',
  'starting' => '启动中',
  'stopping' => '停止中',
  'stopped' => '已停止',
  'error' => '异常',
  _ => '未连接',
};

Color easytierStateColor(BuildContext context, String state) {
  final colorScheme = context.colorScheme;
  return switch (state) {
    'running' => const Color(0xFF22A06B),
    'starting' || 'stopping' => const Color(0xFFE59A1A),
    'error' => colorScheme.error,
    _ => colorScheme.outline,
  };
}

class _EasytierRow {
  final bool self;
  final String ipv4;
  final String hostname;
  final String route;
  final String protocol;
  final String latency;
  final String upload;
  final String download;
  final String loss;
  final String nat;
  final String version;
  final EasytierPeer? peer;
  final EasytierNode? node;

  const _EasytierRow({
    required this.self,
    required this.ipv4,
    required this.hostname,
    required this.route,
    required this.protocol,
    required this.latency,
    required this.upload,
    required this.download,
    required this.loss,
    required this.nat,
    required this.version,
    this.peer,
    this.node,
  });
}

List<_EasytierRow> _rowsFor(EasytierStatus status) {
  final rows = <_EasytierRow>[];
  final node = status.node;
  if (node != null) {
    rows.add(
      _EasytierRow(
        self: true,
        ipv4: node.ipv4,
        hostname: node.hostname,
        route: '本机',
        protocol: '-',
        latency: '-',
        upload: '-',
        download: '-',
        loss: '-',
        nat: node.natType,
        version: node.version,
        node: node,
      ),
    );
  }
  for (final peer in status.peers) {
    rows.add(
      _EasytierRow(
        self: false,
        ipv4: peer.ipv4,
        hostname: peer.hostname,
        route: peer.route,
        protocol: peer.protocol,
        latency: peer.latencyMs <= 0
            ? '0.0 ms'
            : '${peer.latencyMs.toStringAsFixed(1)} ms',
        upload: formatEasytierBytes(peer.txBytes),
        download: formatEasytierBytes(peer.rxBytes),
        loss: '${(peer.lossRate * 100).toStringAsFixed(1)}%',
        nat: peer.natType,
        version: peer.version,
        peer: peer,
      ),
    );
  }
  return rows;
}

class EasytierPage extends ConsumerStatefulWidget {
  const EasytierPage({super.key});

  @override
  ConsumerState<EasytierPage> createState() => _EasytierPageState();
}

class _EasytierPageState extends ConsumerState<EasytierPage> {
  Timer? _timer;
  List<EasytierStatus> _statuses = const [];
  String? _selectedName;
  String _error = '';
  bool _loading = true;
  bool _starting = false;
  int _request = 0;

  EasytierStatus? get _selected {
    if (_statuses.isEmpty) return null;
    for (final status in _statuses) {
      if (status.name == _selectedName) return status;
    }
    return _statuses.first;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_starting) return;
    final request = ++_request;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final statuses = await clashCore.getEasytierStatuses();
      if (!mounted || request != _request) return;
      setState(() {
        _statuses = statuses;
        _loading = false;
        _error = '';
        if (statuses.isNotEmpty &&
            !statuses.any((status) => status.name == _selectedName)) {
          _selectedName = statuses.first.name;
        }
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _start() async {
    final status = _selected;
    if (status == null || _starting) return;
    setState(() {
      _starting = true;
      _error = '';
    });
    try {
      final value = await clashCore.startEasytier(status.name);
      if (!mounted) return;
      if (value == null) {
        setState(() => _error = 'EasyTier 启动失败：内核没有返回状态');
      } else {
        setState(() {
          _statuses = [
            for (final item in _statuses)
              item.name == value.name ? value : item,
          ];
          _selectedName = value.name;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
      if (mounted) unawaited(_refresh(silent: true));
    }
  }

  void _showDetails(_EasytierRow row) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _EasytierDetailSheet(row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _selected;
    final rows = status == null ? const <_EasytierRow>[] : _rowsFor(status);
    return CommonScaffold(
      title: 'EasyTier 组网',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _refresh,
          icon: const AppIcon(Icons.refresh_rounded),
        ),
      ],
      body: ToolPageBody(
        maxWidth: 1200,
        children: [
          if (_error.isNotEmpty) ...[
            ToolNote(
              icon: Icons.error_outline_rounded,
              text: _error,
              color: context.colorScheme.error,
            ),
            const SizedBox(height: 12),
          ],
          if (_statuses.isEmpty)
            _EasytierEmpty(loading: _loading)
          else ...[
            _EasytierOverview(
              statuses: _statuses,
              selected: status,
              starting: _starting,
              onSelect: (name) => setState(() => _selectedName = name),
              onStart: _start,
            ),
            const SizedBox(height: 12),
            if (status != null && status.hasError) ...[
              ToolNote(
                icon: Icons.warning_amber_rounded,
                text: status.error,
                color: context.colorScheme.error,
              ),
              const SizedBox(height: 12),
            ],
            if (status != null && status.isIdle)
              ToolNote(
                icon: Icons.power_settings_new_rounded,
                text: 'EasyTier 尚未启动。点击“连接”后才会创建实例并加入虚拟网络。',
              )
            else if (status != null && rows.isEmpty)
              ToolNote(
                icon: Icons.hourglass_empty_rounded,
                text: 'EasyTier 已连接，但暂时没有可显示的节点。',
              )
            else if (status != null) ...[
              ToolSectionHeader('节点 (${rows.length})'),
              _EasytierTable(rows: rows, onTap: _showDetails),
            ],
          ],
        ],
      ),
    );
  }
}

class _EasytierEmpty extends StatelessWidget {
  final bool loading;

  const _EasytierEmpty({required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const ToolNote(
      icon: Icons.lan_outlined,
      text:
          '当前配置没有 type: easytier 节点。\n'
          '请在配置/覆写里加入 EasyTier 出站，并确认使用的是 standard 构建。',
    );
  }
}

class _EasytierOverview extends StatelessWidget {
  final List<EasytierStatus> statuses;
  final EasytierStatus? selected;
  final bool starting;
  final ValueChanged<String> onSelect;
  final VoidCallback onStart;

  const _EasytierOverview({
    required this.statuses,
    required this.selected,
    required this.starting,
    required this.onSelect,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final status = selected;
    if (status == null) return const SizedBox.shrink();
    final node = status.node;
    final color = easytierStateColor(context, status.state);
    return ToolSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.name.isEmpty ? 'EasyTier' : status.name,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${easytierStateLabel(status.state)}'
                      '${status.network.isEmpty ? '' : ' · ${status.network}'}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (statuses.length > 1)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: status.name,
                    items: [
                      for (final item in statuses)
                        DropdownMenuItem(
                          value: item.name,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) onSelect(value);
                    },
                  ),
                ),
            ],
          ),
          if (node != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: '虚拟 IP', value: node.ipv4),
                if (node.hostname.isNotEmpty)
                  _InfoChip(label: '主机名', value: node.hostname),
                if (node.natType.isNotEmpty)
                  _InfoChip(label: 'NAT', value: node.natType),
                if (node.version.isNotEmpty)
                  _InfoChip(label: '版本', value: node.version),
              ],
            ),
          ],
          if (status.isIdle) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: starting ? null : onStart,
                icon: starting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(starting ? '启动中…' : '连接'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label  $value',
        style: context.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EasytierTable extends StatelessWidget {
  final List<_EasytierRow> rows;
  final ValueChanged<_EasytierRow> onTap;

  const _EasytierTable({required this.rows, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ToolSurface(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          horizontalMargin: 12,
          columnSpacing: 18,
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 52,
          headingRowColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHigh,
          ),
          columns: const [
            DataColumn(label: Text('虚拟IPv4')),
            DataColumn(label: Text('主机名')),
            DataColumn(label: Text('路由')),
            DataColumn(label: Text('协议')),
            DataColumn(label: Text('延迟')),
            DataColumn(label: Text('上传')),
            DataColumn(label: Text('下载')),
            DataColumn(label: Text('丢包')),
            DataColumn(label: Text('NAT类型')),
            DataColumn(label: Text('内核版本')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                onSelectChanged: (_) => onTap(row),
                cells: [
                  DataCell(Text(row.ipv4)),
                  DataCell(Text(row.hostname)),
                  DataCell(Text(row.route)),
                  DataCell(Text(row.protocol)),
                  DataCell(Text(row.latency)),
                  DataCell(Text(row.upload)),
                  DataCell(Text(row.download)),
                  DataCell(Text(row.loss)),
                  DataCell(Text(row.nat)),
                  DataCell(Text(row.version)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EasytierDetailSheet extends StatelessWidget {
  final _EasytierRow row;

  const _EasytierDetailSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final peer = row.peer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.self
                  ? '本机'
                  : (row.hostname.isEmpty ? row.ipv4 : row.hostname),
              style: context.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _DetailRow(label: '虚拟IPv4', value: row.ipv4),
            _DetailRow(label: '主机名', value: row.hostname),
            _DetailRow(label: '路由', value: row.route),
            _DetailRow(label: '协议', value: row.protocol),
            _DetailRow(label: '延迟', value: row.latency),
            _DetailRow(label: '上传', value: row.upload),
            _DetailRow(label: '下载', value: row.download),
            _DetailRow(label: '丢包率', value: row.loss),
            _DetailRow(label: 'NAT类型', value: row.nat),
            _DetailRow(label: '内核版本', value: row.version),
            if (peer != null) ...[
              _DetailRow(label: 'peer id', value: '${peer.peerId}'),
              _DetailRow(label: 'cost', value: '${peer.cost}'),
              if (peer.nextHopPeerId != 0)
                _DetailRow(label: '下一跳', value: '${peer.nextHopPeerId}'),
            ],
            if (node != null) ...[
              if (node.listeners.isNotEmpty)
                _DetailRow(label: '监听', value: node.listeners.join('\n')),
              if (node.proxyCidrs.isNotEmpty)
                _DetailRow(label: '导出网段', value: node.proxyCidrs.join('\n')),
              if (node.publicIps.isNotEmpty)
                _DetailRow(label: '公网 IP', value: node.publicIps.join('\n')),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: context.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
