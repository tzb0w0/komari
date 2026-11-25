package client

import (
	"github.com/gin-gonic/gin"
	"github.com/komari-monitor/komari/internal/config"
	"github.com/komari-monitor/komari/web/api"
)

// GetAgentSettings 返回探针需要的采集参数。
// 探针在启动时（以及之后定期）带 token 拉取，实现「面板改一次、全节点生效」。
func GetAgentSettings(c *gin.Context) {
	hours, err := config.GetAs[int](config.LineDetectIntervalKey, 24)
	if err != nil || hours <= 0 {
		hours = 24
	}
	minutes, err := config.GetAs[int](config.RetransmitIntervalKey, 30)
	if err != nil || minutes <= 0 {
		minutes = 30
	}
	api.RespondSuccess(c, gin.H{
		"line_detect_interval_hours":  hours,
		"retransmit_interval_minutes": minutes,
	})
}
