package easytier

import (
	"context"
	"encoding/binary"
	"math"
	"testing"

	apiinstance "github.com/easytier/easytier/easytier-go/proto/api/instance"
	"github.com/easytier/easytier/easytier-go/proto/common"
)

func int32Ptr(value int32) *int32 { return &value }

func ipv4Inet(octets [4]byte, prefix uint32) *common.Ipv4Inet {
	return &common.Ipv4Inet{
		Address:       &common.Ipv4Addr{Addr: binary.BigEndian.Uint32(octets[:])},
		NetworkLength: prefix,
	}
}

func testUUID(part1, part2, part3, part4 uint32) *common.UUID {
	return &common.UUID{
		Part1: part1,
		Part2: part2,
		Part3: part3,
		Part4: part4,
	}
}

func TestUUIDString(t *testing.T) {
	got := uuidString(testUUID(0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00))
	want := "11223344-5566-7788-99aa-bbccddeeff00"
	if got != want {
		t.Fatalf("uuidString() = %q, want %q", got, want)
	}
	if got := uuidString(nil); got != "" {
		t.Fatalf("uuidString(nil) = %q, want empty", got)
	}
}

func TestDisplayTunnelType(t *testing.T) {
	cases := []struct {
		name   string
		tunnel *common.TunnelInfo
		want   string
	}{
		{
			name: "ipv4",
			tunnel: &common.TunnelInfo{
				TunnelType:         "tcp",
				ResolvedRemoteAddr: &common.Url{Url: "tcp://1.2.3.4:11010"},
			},
			want: "tcp",
		},
		{
			name: "ipv6 gets suffix",
			tunnel: &common.TunnelInfo{
				TunnelType:         "udp",
				ResolvedRemoteAddr: &common.Url{Url: "udp://[2001:db8::1]:11010"},
			},
			want: "udp6",
		},
		{
			name: "already suffixed",
			tunnel: &common.TunnelInfo{
				TunnelType: "udp6",
			},
			want: "udp6",
		},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := displayTunnelType(test.tunnel); got != test.want {
				t.Fatalf("displayTunnelType() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestBuildPeers(t *testing.T) {
	defaultID := testUUID(0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00)
	p2pPeer := &apiinstance.PeerInfo{
		PeerId:        1,
		DefaultConnId: defaultID,
		Conns: []*apiinstance.PeerConnInfo{
			{
				ConnId:   "11223344-5566-7788-99aa-bbccddeeff00",
				Stats:    &apiinstance.PeerConnStats{LatencyUs: 12000, TxBytes: 1000, RxBytes: 2000},
				LossRate: 0.01,
				Tunnel: &common.TunnelInfo{
					TunnelType:         "tcp",
					ResolvedRemoteAddr: &common.Url{Url: "tcp://[2001:db8::1]:11010"},
				},
			},
		},
	}
	relayPeer := &apiinstance.PeerInfo{
		PeerId: 2,
		Conns: []*apiinstance.PeerConnInfo{
			{
				ConnId:   "aabbccdd-1122-3344-5566-778899aabbcc",
				Stats:    &apiinstance.PeerConnStats{LatencyUs: 45000, TxBytes: 10, RxBytes: 20},
				LossRate: 0.02,
				Tunnel: &common.TunnelInfo{
					TunnelType:         "udp",
					ResolvedRemoteAddr: &common.Url{Url: "udp://1.2.3.4:11010"},
				},
			},
		},
	}
	peers := []*apiinstance.PeerInfo{p2pPeer, relayPeer}
	routes := []*apiinstance.Route{
		{
			PeerId:                  2,
			Ipv4Addr:                ipv4Inet([4]byte{10, 126, 126, 1}, 24),
			Hostname:                "nas",
			Cost:                    2,
			PathLatency:             99,
			PathLatencyLatencyFirst: int32Ptr(45),
			StunInfo:                &common.StunInfo{UdpNatType: common.NatType_FullCone},
			NextHopPeerId:           1,
			Version:                 "",
		},
		{
			PeerId:   1,
			Ipv4Addr: ipv4Inet([4]byte{10, 126, 126, 9}, 24),
			Hostname: "PublicServer_vps",
			Cost:     1,
			StunInfo: &common.StunInfo{UdpNatType: common.NatType_PortRestricted},
			Version:  "2.7.0",
		},
		{
			PeerId:   99,
			Ipv4Addr: ipv4Inet([4]byte{10, 126, 126, 99}, 24),
			Hostname: "self",
			Cost:     1,
		},
	}
	self := &StatusNode{PeerID: 99}

	got := buildPeers(peers, routes, self)
	if len(got) != 2 {
		t.Fatalf("buildPeers() returned %d rows, want 2", len(got))
	}
	if got[0].Hostname != "PublicServer_vps" {
		t.Fatalf("public server should sort first, got %q", got[0].Hostname)
	}
	if got[0].Route != "p2p" || got[0].LatencyMs != 12 || got[0].Protocol != "tcp6" {
		t.Fatalf("unexpected p2p row: %+v", got[0])
	}
	if got[0].IPv4 != "10.126.126.9/24" {
		t.Fatalf("unexpected p2p IPv4: %q", got[0].IPv4)
	}
	if got[0].TxBytes != 1000 || got[0].RxBytes != 2000 || math.Abs(got[0].LossRate-0.01) > 1e-6 {
		t.Fatalf("unexpected p2p counters: %+v", got[0])
	}
	if got[0].NATType != "PortRestricted" {
		t.Fatalf("unexpected p2p NAT: %q", got[0].NATType)
	}

	relay := got[1]
	if relay.Route != "relay(2)" || relay.LatencyMs != 45 {
		t.Fatalf("unexpected relay row: %+v", relay)
	}
	if relay.Protocol != "udp" || relay.Version != "unknown" {
		t.Fatalf("unexpected relay fields: %+v", relay)
	}
	if relay.NextHopPeerID != 1 {
		t.Fatalf("unexpected relay next hop: %d", relay.NextHopPeerID)
	}
}

func TestBuildStatusNilInstance(t *testing.T) {
	status := BuildStatus(context.Background(), "ET-Home", "idle", "home", "", nil, nil)
	if status.Name != "ET-Home" || status.State != "idle" || status.Node != nil {
		t.Fatalf("unexpected idle status: %+v", status)
	}
	if len(status.Peers) != 0 {
		t.Fatalf("idle status should have no peers, got %d", len(status.Peers))
	}
}
