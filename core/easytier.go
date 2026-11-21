package main

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	easytiercomp "github.com/metacubex/mihomo/component/easytier"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// easytierStatusProvider is implemented by outbound.EasyTier. Keeping the
// interface consumer-side avoids importing adapter/outbound from this package.
type easytierStatusProvider interface {
	EasytierStatus(context.Context) (*easytiercomp.Status, error)
	EasytierStart(context.Context) error
}

// adapterUnwrapper is implemented by outbound wrappers such as
// autoCloseProxyAdapter. Those wrappers embed the C.ProxyAdapter interface,
// so methods added on the concrete outbound are not promoted to the wrapper.
type adapterUnwrapper interface {
	UnwrapAdapter() C.ProxyAdapter
}

type easytierParams struct {
	Name string `json:"name"`
}

func parseEasytierParams(raw string) easytierParams {
	var params easytierParams
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return params
	}
	_ = json.Unmarshal([]byte(raw), &params)
	return params
}

func unwrapAdapter(adapter C.ProxyAdapter) C.ProxyAdapter {
	for adapter != nil {
		unwrapper, ok := adapter.(adapterUnwrapper)
		if !ok {
			return adapter
		}
		next := unwrapper.UnwrapAdapter()
		if next == nil || next == adapter {
			return adapter
		}
		adapter = next
	}
	return adapter
}

func easytierStatusProviderOf(adapter C.ProxyAdapter) (easytierStatusProvider, bool) {
	provider, ok := unwrapAdapter(adapter).(easytierStatusProvider)
	return provider, ok
}

func easytiertargets() []struct {
	name     string
	provider easytierStatusProvider
} {
	proxies := tunnel.Proxies()
	targets := make([]struct {
		name     string
		provider easytierStatusProvider
	}, 0, len(proxies))
	for name, proxy := range proxies {
		if proxy == nil || proxy.Type() != C.EasyTier {
			continue
		}
		provider, ok := easytierStatusProviderOf(proxy.Adapter())
		if !ok {
			continue
		}
		targets = append(targets, struct {
			name     string
			provider easytierStatusProvider
		}{name: name, provider: provider})
	}
	sort.Slice(targets, func(i, j int) bool { return targets[i].name < targets[j].name })
	return targets
}

func handleGetEasytierStatus(raw string) (any, error) {
	params := parseEasytierParams(raw)
	targets := easytiertargets()
	if params.Name != "" {
		for _, target := range targets {
			if target.name != params.Name {
				continue
			}
			return easytierStatus(target.name, target.provider)
		}
		return nil, errors.New("EasyTier proxy not found: " + params.Name)
	}
	statuses := make([]*easytiercomp.Status, 0, len(targets))
	for _, target := range targets {
		status, err := easytierStatus(target.name, target.provider)
		if err != nil {
			status = &easytiercomp.Status{
				Name:      target.name,
				State:     "error",
				UpdatedAt: time.Now().UnixMilli(),
				Peers:     []easytiercomp.StatusPeer{},
				Error:     err.Error(),
			}
		}
		statuses = append(statuses, status)
	}
	return statuses, nil
}

func easytierStatus(name string, provider easytierStatusProvider) (*easytiercomp.Status, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	status, err := provider.EasytierStatus(ctx)
	if err != nil {
		return nil, err
	}
	if status == nil {
		return nil, errors.New("EasyTier returned no status")
	}
	if status.Name == "" {
		status.Name = name
	}
	return status, nil
}

func handleStartEasytier(raw string) (any, error) {
	params := parseEasytierParams(raw)
	if params.Name == "" {
		return nil, errors.New("EasyTier start requires a proxy name")
	}
	for _, target := range easytiertargets() {
		if target.name != params.Name {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
		defer cancel()
		if err := target.provider.EasytierStart(ctx); err != nil {
			return nil, err
		}
		return easytierStatus(target.name, target.provider)
	}
	return nil, errors.New("EasyTier proxy not found: " + params.Name)
}
