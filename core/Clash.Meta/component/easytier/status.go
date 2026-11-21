package easytier

import (
	"context"
	"fmt"
	"net/netip"
	"net/url"
	"sort"
	"strings"
	"time"

	corehost "github.com/easytier/easytier/easytier-go"
	apiinstance "github.com/easytier/easytier/easytier-go/proto/api/instance"
	"github.com/easytier/easytier/easytier-go/proto/common"
)

// Status is the read-only snapshot exposed to the Android UI.
//
// NodeInfo.Config is intentionally not part of this DTO: it contains the
// network secret and, in secure mode, the local private key.
type Status struct {
	Name       string       `json:"name"`
	State      string       `json:"state"`
	Network    string       `json:"network,omitempty"`
	InstanceID string       `json:"instanceId,omitempty"`
	UpdatedAt  int64        `json:"updatedAt"`
	Node       *StatusNode  `json:"node,omitempty"`
	Peers      []StatusPeer `json:"peers"`
	Error      string       `json:"error,omitempty"`
}

type StatusNode struct {
	PeerID     uint32   `json:"peerId"`
	IPv4       string   `json:"ipv4,omitempty"`
	Hostname   string   `json:"hostname,omitempty"`
	Version    string   `json:"version,omitempty"`
	NATType    string   `json:"natType,omitempty"`
	PublicIPs  []string `json:"publicIps,omitempty"`
	Listeners  []string `json:"listeners,omitempty"`
	ProxyCIDRs []string `json:"proxyCidrs,omitempty"`
}

type StatusPeer struct {
	PeerID        uint32  `json:"peerId"`
	IPv4          string  `json:"ipv4,omitempty"`
	Hostname      string  `json:"hostname,omitempty"`
	Route         string  `json:"route,omitempty"`
	Protocol      string  `json:"protocol,omitempty"`
	LatencyMs     float64 `json:"latencyMs"`
	TxBytes       uint64  `json:"txBytes"`
	RxBytes       uint64  `json:"rxBytes"`
	LossRate      float64 `json:"lossRate"`
	NATType       string  `json:"natType,omitempty"`
	Version       string  `json:"version,omitempty"`
	Cost          int32   `json:"cost"`
	NextHopPeerID uint32  `json:"nextHopPeerId,omitempty"`
}

// StateName converts the EasyTier host state into the UI state vocabulary.
func StateName(state corehost.State) string {
	switch state {
	case corehost.StateCreated:
		return "starting"
	case corehost.StateStarting:
		return "starting"
	case corehost.StateRunning:
		return "running"
	case corehost.StateStopping:
		return "stopping"
	case corehost.StateStopped:
		return "stopped"
	default:
		return "idle"
	}
}

// BuildStatus reads one EasyTier instance and returns a UI-ready snapshot.
// A nil instance means the outbound has not started yet (lazy start).
func BuildStatus(
	ctx context.Context,
	name string,
	state string,
	network string,
	instanceID string,
	instance *corehost.Instance,
	lastErr error,
) *Status {
	status := &Status{
		Name:       name,
		State:      state,
		Network:    network,
		InstanceID: instanceID,
		UpdatedAt:  time.Now().UnixMilli(),
		Peers:      []StatusPeer{},
	}
	if lastErr != nil {
		status.Error = lastErr.Error()
	}
	if instance == nil {
		return status
	}

	nodeInfo, nodeErr := instance.ShowNodeInfo(ctx)
	if nodeErr != nil {
		status.Error = nodeErr.Error()
	} else if nodeInfo != nil {
		status.Node = nodeFromInfo(nodeInfo)
	}

	peers, peerErr := instance.ListPeer(ctx)
	if peerErr != nil {
		status.Error = peerErr.Error()
		return status
	}
	routes, routeErr := instance.ListRoute(ctx)
	if routeErr != nil {
		status.Error = routeErr.Error()
		return status
	}
	status.Peers = buildPeers(peers, routes, status.Node)
	return status
}

func nodeFromInfo(info *apiinstance.NodeInfo) *StatusNode {
	node := &StatusNode{
		PeerID:     info.GetPeerId(),
		IPv4:       info.GetIpv4Addr(),
		Hostname:   info.GetHostname(),
		Version:    info.GetVersion(),
		PublicIPs:  info.GetStunInfo().GetPublicIp(),
		Listeners:  info.GetListeners(),
		ProxyCIDRs: info.GetProxyCidrs(),
	}
	if stun := info.GetStunInfo(); stun != nil {
		node.NATType = natTypeName(int32(stun.GetUdpNatType()))
	}
	return node
}

func buildPeers(
	peerInfos []*apiinstance.PeerInfo,
	routes []*apiinstance.Route,
	self *StatusNode,
) []StatusPeer {
	byID := make(map[uint32]*apiinstance.PeerInfo, len(peerInfos))
	for _, peer := range peerInfos {
		if peer != nil {
			byID[peer.GetPeerId()] = peer
		}
	}

	peers := make([]StatusPeer, 0, len(routes))
	for _, route := range routes {
		if route == nil {
			continue
		}
		if self != nil && route.GetPeerId() == self.PeerID {
			continue
		}
		peerInfo := byID[route.GetPeerId()]
		peers = append(peers, buildPeer(route, peerInfo))
	}

	sort.SliceStable(peers, func(i, j int) bool {
		a, b := peers[i], peers[j]
		aPublic := strings.HasPrefix(a.Hostname, "PublicServer_")
		bPublic := strings.HasPrefix(b.Hostname, "PublicServer_")
		if aPublic != bPublic {
			return aPublic
		}
		aAddr := ipv4Key(a.IPv4)
		bAddr := ipv4Key(b.IPv4)
		if cmp := aAddr.Compare(bAddr); cmp != 0 {
			return cmp < 0
		}
		return a.Hostname < b.Hostname
	})
	return peers
}

func buildPeer(route *apiinstance.Route, peer *apiinstance.PeerInfo) StatusPeer {
	cost := route.GetCost()
	result := StatusPeer{
		PeerID:        route.GetPeerId(),
		IPv4:          formatIPv4Inet(route.GetIpv4Addr()),
		Hostname:      route.GetHostname(),
		Route:         routeName(cost),
		Protocol:      connProtocols(peer),
		LossRate:      lossRate(peer),
		NATType:       natType(route.GetStunInfo()),
		Version:       route.GetVersion(),
		Cost:          cost,
		NextHopPeerID: route.GetNextHopPeerId(),
	}
	if result.Version == "" {
		result.Version = "unknown"
	}
	if cost == 1 {
		result.LatencyMs = peerLatency(peer)
	} else {
		result.LatencyMs = float64(route.GetPathLatencyLatencyFirst())
	}
	result.TxBytes, result.RxBytes = peerBytes(peer)
	return result
}

func routeName(cost int32) string {
	if cost == 1 {
		return "p2p"
	}
	return fmt.Sprintf("relay(%d)", cost)
}

func peerLatency(peer *apiinstance.PeerInfo) float64 {
	if peer == nil {
		return 0
	}
	defaultID := uuidString(peer.GetDefaultConnId())
	min := uint64(0)
	for _, conn := range peer.GetConns() {
		stats := conn.GetStats()
		if stats == nil {
			continue
		}
		if defaultID != "" && conn.GetConnId() == defaultID {
			return float64(stats.GetLatencyUs()) / 1000
		}
		if min == 0 || stats.GetLatencyUs() < min {
			min = stats.GetLatencyUs()
		}
	}
	return float64(min) / 1000
}

func peerBytes(peer *apiinstance.PeerInfo) (tx uint64, rx uint64) {
	if peer == nil {
		return 0, 0
	}
	for _, conn := range peer.GetConns() {
		stats := conn.GetStats()
		if stats == nil {
			continue
		}
		tx += stats.GetTxBytes()
		rx += stats.GetRxBytes()
	}
	return tx, rx
}

func lossRate(peer *apiinstance.PeerInfo) float64 {
	if peer == nil {
		return 0
	}
	defaultID := uuidString(peer.GetDefaultConnId())
	var first *apiinstance.PeerConnInfo
	for _, conn := range peer.GetConns() {
		if conn == nil {
			continue
		}
		if first == nil {
			first = conn
		}
		if defaultID != "" && conn.GetConnId() == defaultID {
			return float64(conn.GetLossRate())
		}
	}
	if first != nil {
		return float64(first.GetLossRate())
	}
	return 0
}

func connProtocols(peer *apiinstance.PeerInfo) string {
	if peer == nil {
		return ""
	}
	seen := make(map[string]struct{}, len(peer.GetConns()))
	protocols := make([]string, 0, len(peer.GetConns()))
	for _, conn := range peer.GetConns() {
		protocol := displayTunnelType(conn.GetTunnel())
		if protocol == "" {
			continue
		}
		if _, ok := seen[protocol]; ok {
			continue
		}
		seen[protocol] = struct{}{}
		protocols = append(protocols, protocol)
	}
	return strings.Join(protocols, ",")
}

func natType(stun *common.StunInfo) string {
	if stun == nil {
		return "Unknown"
	}
	return natTypeName(int32(stun.GetUdpNatType()))
}

func natTypeName(value int32) string {
	if name, ok := common.NatType_name[value]; ok {
		return name
	}
	return "Unknown"
}

func formatIPv4Inet(inet *common.Ipv4Inet) string {
	if inet == nil || inet.GetAddress() == nil {
		return ""
	}
	addr := IPv4FromUint32(inet.GetAddress().GetAddr())
	if length := inet.GetNetworkLength(); length > 0 && length <= 32 {
		return netip.PrefixFrom(addr, int(length)).String()
	}
	return addr.String()
}

func ipv4Key(value string) netip.Addr {
	if slash := strings.IndexByte(value, '/'); slash >= 0 {
		value = value[:slash]
	}
	addr, err := netip.ParseAddr(value)
	if err != nil || !addr.Is4() {
		return netip.Addr{}
	}
	return addr
}

// uuidString renders EasyTier's four-part UUID in the standard
// 8-4-4-4-12 form used by PeerConnInfo.ConnId.
func uuidString(uuid *common.UUID) string {
	if uuid == nil {
		return ""
	}
	return fmt.Sprintf(
		"%08x-%04x-%04x-%04x-%012x",
		uuid.GetPart1(),
		uint16(uuid.GetPart2()>>16),
		uint16(uuid.GetPart2()),
		uint16(uuid.GetPart3()>>16),
		(uint64(uint16(uuid.GetPart3()))<<32)|uint64(uuid.GetPart4()),
	)
}

// displayTunnelType mirrors EasyTier's display_tunnel_type(): the scheme is
// suffixed with 6 when the tunnel endpoint is IPv6.
func displayTunnelType(tunnel *common.TunnelInfo) string {
	if tunnel == nil {
		return ""
	}
	protocol := tunnel.GetTunnelType()
	if protocol == "" {
		return ""
	}
	if strings.HasSuffix(protocol, "6") || !tunnelIsIPv6(tunnel) {
		return protocol
	}
	return protocol + "6"
}

func tunnelIsIPv6(tunnel *common.TunnelInfo) bool {
	for _, raw := range []string{
		tunnel.GetResolvedRemoteAddr().GetUrl(),
		tunnel.GetLocalAddr().GetUrl(),
		tunnel.GetRemoteAddr().GetUrl(),
	} {
		if raw == "" {
			continue
		}
		parsed, err := url.Parse(raw)
		if err != nil {
			continue
		}
		host := parsed.Hostname()
		if host == "" {
			continue
		}
		if ip, err := netip.ParseAddr(host); err == nil && !ip.Is4() {
			return true
		}
	}
	return false
}
