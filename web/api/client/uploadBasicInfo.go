package client

import (
	"encoding/json"
	"net"

	"github.com/komari-monitor/komari/database/clients"
	"github.com/komari-monitor/komari/internal/config"
	"github.com/komari-monitor/komari/utils/geoip"
)

func getClientIPType(ip net.IP) int {
	// 0:ipv4 1:ipv6 -1:错误的输入
	if ip == nil {
		return -1
	}
	if ip.To4() == nil {
		return 1
	}
	return 0
}

func saveClientBasicInfo(info map[string]interface{}, uuid string, fallbackIP string) error {
	info["uuid"] = uuid
	applyFallbackClientIP(info, fallbackIP)
	appendClientRegionFromGeoIP(info)
	normalizeLineInfo(info)
	return clients.SaveClientInfo(info)
}

// normalizeLineInfo 将 agent 上报的 line 对象序列化为 line_info JSON 字符串，
// 以便存入 Client 模型的 varchar 字段。数据库只保存 line_info，移除原始 line。
func normalizeLineInfo(info map[string]interface{}) {
	line, exists := info["line"]
	if !exists || line == nil {
		return
	}
	// 已经是字符串则直接用
	if s, ok := line.(string); ok {
		info["line_info"] = s
		delete(info, "line")
		return
	}
	if b, err := json.Marshal(line); err == nil {
		info["line_info"] = string(b)
	}
	delete(info, "line")
}

func applyFallbackClientIP(info map[string]interface{}, fallbackIP string) {
	if hasClientIP(info) {
		return
	}
	ip := net.ParseIP(fallbackIP)

	switch getClientIPType(ip) {
	case 0:
		info["ipv4"] = fallbackIP
	case 1:
		info["ipv6"] = fallbackIP
	}
}

func hasClientIP(info map[string]interface{}) bool {
	if ipv4, ok := info["ipv4"].(string); ok && ipv4 != "" {
		return true
	}
	if ipv6, ok := info["ipv6"].(string); ok && ipv6 != "" {
		return true
	}
	return false
}

func appendClientRegionFromGeoIP(info map[string]interface{}) {
	cfg, err := config.GetAs[bool](config.GeoIpEnabledKey)
	if err != nil || !cfg {
		return
	}

	for _, key := range []string{"ipv4", "ipv6"} {
		ipStr, ok := info[key].(string)
		if !ok || ipStr == "" {
			continue
		}
		ip := net.ParseIP(ipStr)
		if ip == nil {
			continue
		}
		record, _ := geoip.GetGeoInfo(ip)
		if record == nil {
			continue
		}
		region := geoip.GetRegionUnicodeEmoji(record.ISOCode)
		if region == "" {
			continue
		}
		info["region"] = region
		return
	}
}
