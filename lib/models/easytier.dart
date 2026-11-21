class EasytierStatus {
  final String name;
  final String state;
  final String network;
  final String instanceId;
  final int updatedAt;
  final EasytierNode? node;
  final List<EasytierPeer> peers;
  final String error;

  const EasytierStatus({
    this.name = '',
    this.state = 'idle',
    this.network = '',
    this.instanceId = '',
    this.updatedAt = 0,
    this.node,
    this.peers = const [],
    this.error = '',
  });

  bool get isRunning => state == 'running';
  bool get isIdle => state == 'idle';
  bool get hasError => error.isNotEmpty;

  factory EasytierStatus.fromJson(Map<String, Object?> json) {
    final rawPeers = json['peers'];
    return EasytierStatus(
      name: _string(json['name']),
      state: _string(json['state'], 'idle'),
      network: _string(json['network']),
      instanceId: _string(json['instanceId']),
      updatedAt: _int(json['updatedAt']),
      node: json['node'] is Map
          ? EasytierNode.fromJson(
              Map<String, Object?>.from(json['node'] as Map),
            )
          : null,
      peers: rawPeers is List
          ? [
              for (final item in rawPeers)
                if (item is Map)
                  EasytierPeer.fromJson(Map<String, Object?>.from(item)),
            ]
          : const [],
      error: _string(json['error']),
    );
  }
}

class EasytierNode {
  final int peerId;
  final String ipv4;
  final String hostname;
  final String version;
  final String natType;
  final List<String> publicIps;
  final List<String> listeners;
  final List<String> proxyCidrs;

  const EasytierNode({
    this.peerId = 0,
    this.ipv4 = '',
    this.hostname = '',
    this.version = '',
    this.natType = '',
    this.publicIps = const [],
    this.listeners = const [],
    this.proxyCidrs = const [],
  });

  factory EasytierNode.fromJson(Map<String, Object?> json) => EasytierNode(
    peerId: _int(json['peerId']),
    ipv4: _string(json['ipv4']),
    hostname: _string(json['hostname']),
    version: _string(json['version']),
    natType: _string(json['natType']),
    publicIps: _strings(json['publicIps']),
    listeners: _strings(json['listeners']),
    proxyCidrs: _strings(json['proxyCidrs']),
  );
}

class EasytierPeer {
  final int peerId;
  final String ipv4;
  final String hostname;
  final String route;
  final String protocol;
  final double latencyMs;
  final int txBytes;
  final int rxBytes;
  final double lossRate;
  final String natType;
  final String version;
  final int cost;
  final int nextHopPeerId;

  const EasytierPeer({
    this.peerId = 0,
    this.ipv4 = '',
    this.hostname = '',
    this.route = '',
    this.protocol = '',
    this.latencyMs = 0,
    this.txBytes = 0,
    this.rxBytes = 0,
    this.lossRate = 0,
    this.natType = '',
    this.version = '',
    this.cost = 0,
    this.nextHopPeerId = 0,
  });

  factory EasytierPeer.fromJson(Map<String, Object?> json) => EasytierPeer(
    peerId: _int(json['peerId']),
    ipv4: _string(json['ipv4']),
    hostname: _string(json['hostname']),
    route: _string(json['route']),
    protocol: _string(json['protocol']),
    latencyMs: _double(json['latencyMs']),
    txBytes: _int(json['txBytes']),
    rxBytes: _int(json['rxBytes']),
    lossRate: _double(json['lossRate']),
    natType: _string(json['natType']),
    version: _string(json['version']),
    cost: _int(json['cost']),
    nextHopPeerId: _int(json['nextHopPeerId']),
  );
}

String _string(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null) item.toString(),
  ];
}
