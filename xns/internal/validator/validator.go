package validator

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
	"xns/pkg/spec"
)

// ValidateFile reads a spec file and validates it.
func ValidateFile(path string) (*spec.NodeSpec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	var s spec.NodeSpec
	if err := yaml.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("unmarshal yaml: %w", err)
	}

	if err := s.Validate(); err != nil {
		return nil, err
	}

	return &s, nil
}
