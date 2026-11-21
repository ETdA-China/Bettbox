import 'package:bett_box/models/easytier.dart';
import 'package:bett_box/pages/easytier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EasytierStatus.fromJson', () {
    test('parses node and peers', () {
      final status = EasytierStatus.fromJson({
        'name': 'ET-Home',
        'state': 'running',
        'network': 'etda_vpn',
        'instanceId': 'abc',
        'updatedAt': 123,
        'node': {
          'peerId': 51,
          'ipv4': '10.126.126.51/24',
          'hostname': 'phone',
          'version': '2.7.0',
          'natType': 'PortRestricted',
          'listeners': ['tcp://0.0.0.0:11010'],
        },
        'peers': [
          {
            'peerId': 1,
            'ipv4': '10.126.126.1/24',
            'hostname': 'vps',
            'route': 'p2p',
            'protocol': 'tcp6,tcp',
            'latencyMs': 12.5,
            'txBytes': 1000,
            'rxBytes': 2000,
            'lossRate': 0.01,
            'natType': 'FullCone',
            'version': '2.7.0',
            'cost': 1,
          },
        ],
      });

      expect(status.name, 'ET-Home');
      expect(status.isRunning, isTrue);
      expect(status.node?.ipv4, '10.126.126.51/24');
      expect(status.node?.natType, 'PortRestricted');
      expect(status.peers, hasLength(1));
      expect(status.peers.single.protocol, 'tcp6,tcp');
      expect(status.peers.single.latencyMs, 12.5);
      expect(status.peers.single.txBytes, 1000);
      expect(status.peers.single.lossRate, 0.01);
    });

    test('defaults missing collections', () {
      final status = EasytierStatus.fromJson({'state': 'idle'});
      expect(status.isIdle, isTrue);
      expect(status.node, isNull);
      expect(status.peers, isEmpty);
    });
  });

  test('formatEasytierBytes uses decimal units', () {
    expect(formatEasytierBytes(0), '0 B');
    expect(formatEasytierBytes(999), '999 B');
    expect(formatEasytierBytes(1000), '1.0 KB');
    expect(formatEasytierBytes(1500), '1.5 KB');
    expect(formatEasytierBytes(1000000), '1.0 MB');
  });

  test('state labels', () {
    expect(easytierStateLabel('running'), '运行中');
    expect(easytierStateLabel('idle'), '未连接');
    expect(easytierStateLabel('error'), '异常');
  });
}
