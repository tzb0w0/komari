package public

import (
	"embed"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// builtinTheme 是随二进制一起分发的默认前台主题（Komari Glass 定制版）。
// 启动时释放到 data/theme/<short>；版本号变化时会重新释放，保证跟随升级。
// 用户仍可在「主题管理」里切换到其它主题。
//
//go:embed all:builtinTheme
var BuiltinThemeFS embed.FS

const (
	// BuiltinThemeShort 是内嵌主题的标识，必须与 builtinTheme/komari-theme.json 中的 short 一致。
	BuiltinThemeShort = "GlassCustom"
	builtinThemeRoot  = "builtinTheme"
)

type themeManifest struct {
	Short   string `json:"short"`
	Version string `json:"version"`
}

// EnsureBuiltinTheme 把内嵌主题释放到 dataThemeDir/<short>。
// 已安装版本与内嵌版本一致时跳过；版本不同（升级）则覆盖重写。
func EnsureBuiltinTheme(dataThemeDir string) error {
	dest := filepath.Join(dataThemeDir, BuiltinThemeShort)

	builtinVer := manifestVersion(BuiltinThemeFS, builtinThemeRoot+"/komari-theme.json")
	installedVer := manifestVersion(os.DirFS(dest), "komari-theme.json")

	if builtinVer != "" && builtinVer == installedVer {
		if _, err := os.Stat(filepath.Join(dest, "dist", "index.html")); err == nil {
			return nil
		}
	}

	// 清空旧目录，避免残留上一版的 chunk
	if err := os.RemoveAll(dest); err != nil {
		return err
	}

	return fs.WalkDir(BuiltinThemeFS, builtinThemeRoot, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel := strings.TrimPrefix(p, builtinThemeRoot)
		rel = strings.TrimPrefix(rel, "/")
		target := filepath.Join(dest, filepath.FromSlash(rel))

		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := BuiltinThemeFS.ReadFile(p)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	})
}

// manifestVersion 读取 komari-theme.json 的 version；读不到返回空串。
func manifestVersion(fsys fs.FS, path string) string {
	data, err := fs.ReadFile(fsys, path)
	if err != nil {
		return ""
	}
	var m themeManifest
	if err := json.Unmarshal(data, &m); err != nil {
		return ""
	}
	return m.Version
}
