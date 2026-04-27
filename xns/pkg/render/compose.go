package render

import (
	"bytes"
	_ "embed"
	"fmt"
	"strings"
	"text/template"

	"xns/pkg/spec"
)

//go:embed compose.yml.tmpl
var composeTemplate string

// ComposeData holds data for the compose template.
type ComposeData struct {
	Name           string
	Image          string
	Restart        string
	ContainerName  string
	Platform       string
	StopGrace      string
	Ports          []string
	Volumes        []string
	Env            []string
	Command        []string
	Entrypoint     []string
	ExtraHosts     []string
	Networks       []string
	NetworkMode    string
	DependsOn      map[string]map[string]string
	Healthcheck    *HealthcheckData
	Logging        *LoggingData
}

// HealthcheckData holds healthcheck config.
type HealthcheckData struct {
	Test        string
	Interval    string
	Timeout     string
	Retries     int
	StartPeriod string
}

// LoggingData holds logging config.
type LoggingData struct {
	Driver string
	MaxSize string
	MaxFile string
}

// RenderCompose renders a docker-compose.yml service from a NodeSpec.
func RenderCompose(s *spec.NodeSpec) (string, error) {
	if err := s.Validate(); err != nil {
		return "", err
	}

	data, err := buildComposeData(s)
	if err != nil {
		return "", err
	}

	tmpl, err := template.New("compose").Funcs(template.FuncMap{
		"join": strings.Join,
	}).Parse(composeTemplate)
	if err != nil {
		return "", fmt.Errorf("parse template: %w", err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("execute template: %w", err)
	}

	return buf.String(), nil
}

func buildComposeData(s *spec.NodeSpec) (*ComposeData, error) {
	d := &ComposeData{
		Name:    s.Name,
		Image:   s.Image,
		Restart: s.Restart,
	}
	if d.Restart == "" {
		d.Restart = "unless-stopped"
	}

	// Ports
	if s.Ports.RPC != 0 {
		d.Ports = append(d.Ports, fmt.Sprintf("%d:%d", s.Ports.RPC, s.Ports.RPC))
	}
	if s.Ports.WS != 0 {
		d.Ports = append(d.Ports, fmt.Sprintf("%d:%d", s.Ports.WS, s.Ports.WS))
	}
	if s.Ports.P2P != 0 {
		d.Ports = append(d.Ports, fmt.Sprintf("%d:%d", s.Ports.P2P, s.Ports.P2P))
	}
	if s.Ports.Auth != 0 {
		d.Ports = append(d.Ports, fmt.Sprintf("%d:%d", s.Ports.Auth, s.Ports.Auth))
	}

	// Volumes (preserve order from spec if possible; map iteration is random)
	for host, container := range s.Volumes {
		d.Volumes = append(d.Volumes, fmt.Sprintf("%s:%s", host, container))
	}

	// Env
	for k, v := range s.Env {
		d.Env = append(d.Env, fmt.Sprintf("%s=%s", k, v))
	}

	// Command flags
	cmd, err := buildCommand(s)
	if err != nil {
		return nil, err
	}
	d.Command = cmd

	// Extra hosts
	d.ExtraHosts = append(d.ExtraHosts, s.ExtraHosts...)

	// Networks
	d.Networks = append(d.Networks, string(s.Network))

	return d, nil
}

func buildCommand(s *spec.NodeSpec) ([]string, error) {
	var args []string

	// Client-specific flag mappings
	rpcPrefix := s.Client.RPCFlagPrefix()
	wsPrefix := s.Client.WSFlagPrefix()

	// Network / chain
	args = append(args, "--networkid", fmt.Sprintf("%d", s.Network.ChainID()))

	// Data dir
	args = append(args, "--datadir", "/data")

	// RPC
	if s.RPC.Enabled {
		args = append(args, fmt.Sprintf("--%s", rpcPrefix))
		args = append(args, fmt.Sprintf("--%s.addr", rpcPrefix), s.RPC.Host)
		args = append(args, fmt.Sprintf("--%s.port", rpcPrefix), fmt.Sprintf("%d", s.RPC.Port))
		if s.RPC.APIs != "" {
			args = append(args, fmt.Sprintf("--%s.api", rpcPrefix), s.RPC.APIs)
		}
		if s.RPC.VHosts != "" {
			args = append(args, fmt.Sprintf("--%s.vhosts", rpcPrefix), s.RPC.VHosts)
		}
		if s.RPC.CORS != "" {
			args = append(args, fmt.Sprintf("--%s.corsdomain", rpcPrefix), s.RPC.CORS)
		}
	}

	// WS
	if s.WS.Enabled {
		args = append(args, fmt.Sprintf("--%s", wsPrefix))
		args = append(args, fmt.Sprintf("--%s.addr", wsPrefix), s.WS.Host)
		args = append(args, fmt.Sprintf("--%s.port", wsPrefix), fmt.Sprintf("%d", s.WS.Port))
		if s.WS.APIs != "" {
			args = append(args, fmt.Sprintf("--%s.api", wsPrefix), s.WS.APIs)
		}
	}

	// P2P
	if s.Ports.P2P != 0 {
		args = append(args, "--port", fmt.Sprintf("%d", s.Ports.P2P))
	}
	if s.Peers.MaxPeers != 0 {
		args = append(args, "--maxpeers", fmt.Sprintf("%d", s.Peers.MaxPeers))
	}
	for _, node := range s.Peers.Bootnodes {
		args = append(args, "--bootnodes", node)
	}
	for _, node := range s.Peers.StaticNodes {
		args = append(args, "--staticnodes", node)
	}

	// Role-specific flags
	switch s.Role {
	case spec.Masternode:
		args = append(args, "--mine")
		args = append(args, "--masternode")
	case spec.Archive:
		args = append(args, "--syncmode", "full")
		args = append(args, "--gcmode", "archive")
	case spec.RPC:
		args = append(args, "--rpc.gascap", "0")
	}

	// Extra flags
	args = append(args, s.Flags...)

	return args, nil
}
