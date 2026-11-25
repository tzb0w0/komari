package public

import (
	"embed"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// builtinTheme 是随二进制一起分发的默认前台主题（Komari Glass 定制版）。
// 首次启动时释放到 data/theme/<short>，用户仍可在「主题管理」里切换或删除。
//
//go:embed all:builtinTheme
var BuiltinThemeFS embed.FS

const (
	// BuiltinThemeShort 是内嵌主题的标识，必须与 builtinTheme/komari-theme.json 中的 short 一致。
	BuiltinThemeShort = "GlassCustom"
	builtinThemeRoot  = "builtinTheme"
)

// EnsureBuiltinTheme 把内嵌主题释放到 dataThemeDir/<short>。
// 已存在（dist/index.html 可读）时直接跳过，不覆盖用户改动。
func EnsureBuiltinTheme(dataThemeDir string) error {
	dest := filepath.Join(dataThemeDir, BuiltinThemeShort)
	if _, err := os.Stat(filepath.Join(dest, "dist", "index.html")); err == nil {
		return nil
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
