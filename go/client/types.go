package client

// VersionResult mirrors `rigorix.system.version` (`schemas/api/catalog.json`
// `$defs.versionResult`). Field names match the frozen catalog exactly.
type VersionResult struct {
	Name          string   `json:"name"`
	EngineVersion string   `json:"engine_version"`
	APIVersion    string   `json:"api_version"`
	Schemas       []string `json:"schemas"`
	Capabilities  []string `json:"capabilities"`
}
