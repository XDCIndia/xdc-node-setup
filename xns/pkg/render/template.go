package render

import (
	"bytes"
	"fmt"
	"text/template"
)

// RenderTemplate renders a named template with data.
func RenderTemplate(name string, tmpl string, data interface{}) (string, error) {
	t, err := template.New(name).Parse(tmpl)
	if err != nil {
		return "", fmt.Errorf("parse %s: %w", name, err)
	}
	var buf bytes.Buffer
	if err := t.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("execute %s: %w", name, err)
	}
	return buf.String(), nil
}

// TemplateFuncMap returns common template functions.
func TemplateFuncMap() template.FuncMap {
	return template.FuncMap{
		"quote": func(s string) string {
			return fmt.Sprintf("%q", s)
		},
	}
}
