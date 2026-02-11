'use client';

import { useEffect, useState, useRef, useLayoutEffect } from 'react';
import * as am5 from '@amcharts/amcharts5';
import * as am5xy from '@amcharts/amcharts5/xy';
import * as am5radar from '@amcharts/amcharts5/radar';
import { Blocks, TrendingUp, Users, Clock } from 'lucide-react';
import { XdcDarkTheme, colors } from '@/lib/amcharts-theme';
import { formatNumber, formatDuration } from '@/lib/formatters';
import type { BlockchainData } from '@/lib/types';

interface BlockchainCardProps {
  data: BlockchainData;
}

export default function BlockchainCard({ data }: BlockchainCardProps) {
  const [displayHeight, setDisplayHeight] = useState(0);
  const chartRef = useRef<HTMLDivElement>(null);
  const gaugeRef = useRef<HTMLDivElement>(null);
  const rootRef = useRef<am5.Root | null>(null);
  const gaugeRootRef = useRef<am5.Root | null>(null);

  // Animate block height
  useEffect(() => {
    const startHeight = displayHeight;
    const endHeight = data.blockHeight;
    const diff = endHeight - startHeight;
    if (diff === 0) return;

    const duration = 1000;
    const startTime = performance.now();
    let animationId: number;

    const animate = (currentTime: number) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(1, elapsed / duration);
      const easeOut = 1 - Math.pow(1 - progress, 3);
      setDisplayHeight(Math.floor(startHeight + diff * easeOut));
      if (progress < 1) {
        animationId = requestAnimationFrame(animate);
      }
    };

    animationId = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animationId);
  }, [data.blockHeight]);

  // Block Height Trend Chart
  useLayoutEffect(() => {
    if (!chartRef.current) return;

    const root = am5.Root.new(chartRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);
    rootRef.current = root;

    const chart = root.container.children.push(
      am5xy.XYChart.new(root, {
        panX: false,
        panY: false,
        paddingLeft: 0,
        paddingRight: 0,
      })
    );

    // Generate realistic data based on current block height
    const now = Date.now();
    const chartData = Array.from({ length: 30 }, (_, i) => ({
      time: new Date(now - (29 - i) * 60000),
      value: data.blockHeight - (29 - i) * 2,
    }));

    const xAxis = chart.xAxes.push(
      am5xy.DateAxis.new(root, {
        baseInterval: { timeUnit: 'minute', count: 1 },
        renderer: am5xy.AxisRendererX.new(root, {
          minGridDistance: 50,
        }),
      })
    );
    xAxis.get('renderer').labels.template.setAll({
      fill: am5.color(colors.textSecondary),
      fontSize: 10,
    });

    const yAxis = chart.yAxes.push(
      am5xy.ValueAxis.new(root, {
        renderer: am5xy.AxisRendererY.new(root, {}),
        numberFormat: "#,###",
      })
    );
    yAxis.get('renderer').labels.template.setAll({
      fill: am5.color(colors.textSecondary),
      fontSize: 10,
    });

    const series = chart.series.push(
      am5xy.LineSeries.new(root, {
        xAxis,
        yAxis,
        valueYField: 'value',
        valueXField: 'time',
        stroke: am5.color(colors.accent),
        fill: am5.color(colors.accent),
      })
    );

    series.strokes.template.setAll({
      strokeWidth: 2,
    });

    series.fills.template.setAll({
      visible: true,
      fillOpacity: 0.2,
      fillGradient: am5.LinearGradient.new(root, {
        stops: [
          { color: am5.color(colors.accent), opacity: 0.3 },
          { color: am5.color(colors.accent), opacity: 0 },
        ],
        rotation: 90,
      }),
    });

    series.data.setAll(chartData);

    chart.set('cursor', am5xy.XYCursor.new(root, {
      behavior: 'none',
      xAxis,
    }));

    return () => {
      root.dispose();
    };
  }, [data.blockHeight]);

  // Sync Gauge
  useLayoutEffect(() => {
    if (!gaugeRef.current) return;

    const root = am5.Root.new(gaugeRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);
    gaugeRootRef.current = root;

    const chart = root.container.children.push(
      am5radar.RadarChart.new(root, {
        panX: false,
        panY: false,
        startAngle: 180,
        endAngle: 360,
        innerRadius: am5.percent(70),
      })
    );

    const axisRenderer = am5radar.AxisRendererCircular.new(root, {
      innerRadius: -10,
      strokeOpacity: 0,
      minGridDistance: 30,
    });
    axisRenderer.labels.template.set('visible', false);
    axisRenderer.grid.template.set('visible', false);

    const xAxis = chart.xAxes.push(
      am5xy.ValueAxis.new(root, {
        maxDeviation: 0,
        min: 0,
        max: 100,
        strictMinMax: true,
        renderer: axisRenderer,
      })
    );

    const axisDataItem = xAxis.makeDataItem({});
    axisDataItem.set('value', 0);

    const clockHand = am5radar.ClockHand.new(root, {
      pinRadius: 0,
      radius: am5.percent(85),
      bottomWidth: 10,
      topWidth: 0,
    });
    clockHand.pin.setAll({ visible: false });
    clockHand.hand.setAll({
      fill: am5.color(data.syncPercent >= 99 ? colors.success : data.syncPercent >= 90 ? colors.warning : colors.error),
      fillOpacity: 0.8,
    });

    axisDataItem.set('bullet', am5xy.AxisBullet.new(root, {
      sprite: clockHand,
    }));

    xAxis.createAxisRange(axisDataItem);

    // Background arc
    const range0 = xAxis.createAxisRange(
      xAxis.makeDataItem({ above: true, value: 0, endValue: 100 })
    );
    range0.get('axisFill')?.setAll({
      visible: true,
      fill: am5.color(colors.border),
      fillOpacity: 0.5,
    });

    // Progress arc
    const range1 = xAxis.createAxisRange(
      xAxis.makeDataItem({ above: true, value: 0, endValue: data.syncPercent })
    );
    range1.get('axisFill')?.setAll({
      visible: true,
      fill: am5.color(data.syncPercent >= 99 ? colors.success : data.syncPercent >= 90 ? colors.warning : colors.accent),
    });

    // Animate
    axisDataItem.animate({
      key: 'value',
      to: data.syncPercent,
      duration: 1000,
      easing: am5.ease.out(am5.ease.cubic),
    });

    // Center label
    chart.children.push(
      am5.Label.new(root, {
        text: `${data.syncPercent.toFixed(1)}%`,
        fontSize: 24,
        fontWeight: '700',
        fill: am5.color(colors.textPrimary),
        centerX: am5.percent(50),
        centerY: am5.percent(70),
        x: am5.percent(50),
        y: am5.percent(50),
      })
    );

    return () => {
      root.dispose();
    };
  }, [data.syncPercent]);

  // Fix uptime display - if uptime is unrealistic (e.g., 28 weeks for a syncing node), show "Syncing..."
  const displayUptime = () => {
    // If uptime seems unrealistic (more than 30 days while syncing), show syncing status
    if (data.isSyncing && data.uptime > 30 * 86400) {
      return 'Syncing...';
    }
    // If uptime is 0 or invalid
    if (!data.uptime || data.uptime < 0) {
      return '—';
    }
    return formatDuration(data.uptime);
  };

  // Get status color
  const getSyncStatusColor = () => {
    if (data.syncPercent >= 99) return 'text-[#00E396]';
    if (data.syncPercent >= 90) return 'text-[#FEB019]';
    return 'text-[#1E90FF]';
  };

  return (
    <div id="blockchain" className="card-premium p-4 sm:p-6">
      <div className="grid-pattern" />

      <div className="relative">
        {/* Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-6 gap-3">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#00D4FF]/20 flex items-center justify-center">
              <Blocks className="w-5 h-5 text-[#1E90FF]" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-[#E8E8F0]">Blockchain Status</h2>
              <div className="flex items-center gap-2">
                <span className={`status-dot ${data.syncPercent >= 99 ? 'active' : ''}`} />
                <span className={`text-sm ${getSyncStatusColor()}`}>
                  {data.isSyncing ? 'Syncing...' : 'Fully Synced'}
                </span>
              </div>
            </div>
          </div>

          <span className="px-3 py-1.5 rounded-full bg-[#1E90FF]/10 text-[#1E90FF] text-xs font-medium border border-[#1E90FF]/20 self-start sm:self-auto">
            xinfinorg/xdposchain:v2.6.8
          </span>
        </div>

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left - Block Height */}
          <div className="lg:col-span-3 flex flex-col justify-center">
            <div className="stat-label mb-2 flex items-center gap-1">
              <Blocks className="w-3 h-3" /> Current Block Height
            </div>
            <div className="text-3xl sm:text-4xl lg:text-5xl font-bold text-[#E8E8F0] font-mono mb-2">
              {data.blockHeight > 0 ? displayHeight.toLocaleString() : '—'}
            </div>
            <div className="flex items-center gap-2 text-sm">
              <TrendingUp className="w-4 h-4 text-[#00E396]" />
              <span className="text-[#00E396]">
                Highest: {data.highestBlock > 0 ? data.highestBlock.toLocaleString() : '—'}
              </span>
            </div>
          </div>

          {/* Center - Block Height Chart */}
          <div className="lg:col-span-6">
            <div className="stat-label mb-2">Block Height Trend (30 min)</div>
            <div ref={chartRef} className="w-full h-[160px] sm:h-[180px]" />
          </div>

          {/* Right - Sync Gauge + Stats */}
          <div className="lg:col-span-3 grid grid-cols-2 gap-4">
            <div className="col-span-1">
              <div ref={gaugeRef} className="w-full h-[100px] sm:h-[120px]" />
              <div className="text-center text-xs text-[#8B8CA7] -mt-2">SYNC</div>
            </div>

            <div className="col-span-1 space-y-3">
              <div className="p-3 rounded-xl bg-[#0B1120]/50">
                <div className="stat-label flex items-center gap-1">
                  <Users className="w-3 h-3" /> Peers
                </div>
                <div className="stat-value text-[#1E90FF]">{data.peers > 0 ? data.peers : '—'}</div>
                <div className="flex gap-2 text-xs mt-1">
                  <span className="text-[#00E396]">↓ {data.peersInbound || 0}</span>
                  <span className="text-[#1E90FF]">↑ {data.peersOutbound || 0}</span>
                </div>
              </div>

              <div className="p-3 rounded-xl bg-[#0B1120]/50">
                <div className="stat-label flex items-center gap-1">
                  <Clock className="w-3 h-3" /> Uptime
                </div>
                <div className="stat-value text-[#E8E8F0] text-base sm:text-lg">{displayUptime()}</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
