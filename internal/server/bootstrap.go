package server

import (
	"context"
	"fmt"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/komari-monitor/komari/database/dbcore"
	"github.com/komari-monitor/komari/internal/config"
	"github.com/komari-monitor/komari/utils"
	"github.com/komari-monitor/komari/web/public"
)

// Bootstrap initializes the data directory, primary database, and settings.
func (a *App) Bootstrap() error {
	if err := os.MkdirAll("./data/theme", os.ModePerm); err != nil {
		return fmt.Errorf("failed to create theme directory: %w", err)
	}
	if err := os.MkdirAll("./data/plugin", os.ModePerm); err != nil {
		return fmt.Errorf("failed to create plugin directory: %w", err)
	}
	if err := os.MkdirAll("./data/plugin-data", os.ModePerm); err != nil {
		return fmt.Errorf("failed to create plugin storage directory: %w", err)
	}

	// 释放内嵌前台主题（Komari Glass 定制版），并让首次启动直接使用它
	if err := public.EnsureBuiltinTheme("./data/theme"); err != nil {
		fmt.Printf("[WARN] failed to install builtin theme: %v\n", err)
	}

	dbcore.SetVersionID(utils.CurrentVersion + "-" + utils.VersionHash)
	if err := dbcore.Initialize(); err != nil {
		return fmt.Errorf("failed to initialize database: %w", err)
	}
	a.dbReady = true
	a.addCleanup("database", func(context.Context) error { return dbcore.Close() })

	gin.SetMode(gin.ReleaseMode)
	settings, err := config.GetManyAs[config.Settings]()
	if err != nil {
		return fmt.Errorf("failed to load settings: %w", err)
	}
	a.settings = settings

	// 只在首次升级时把「默认主题」换成内嵌主题，之后用户自己的选择不被覆盖
	if err := applyBuiltinThemeOnce(); err != nil {
		fmt.Printf("[WARN] failed to switch to builtin theme: %v\n", err)
	}
	return nil
}

// applyBuiltinThemeOnce 用一个标记文件保证只执行一次。
func applyBuiltinThemeOnce() error {
	const marker = "./data/.builtin-theme-applied"
	if _, err := os.Stat(marker); err == nil {
		return nil
	}
	current, err := config.GetAs[string](config.ThemeKey, "default")
	if err != nil {
		return err
	}
	if current == "" || current == "default" {
		if err := config.Set(config.ThemeKey, public.BuiltinThemeShort); err != nil {
			return err
		}
		fmt.Printf("[INFO] default theme switched to %s\n", public.BuiltinThemeShort)
	}
	if err := os.MkdirAll("./data", 0o755); err != nil {
		return err
	}
	return os.WriteFile(marker, []byte(public.BuiltinThemeShort), 0o644)
}
