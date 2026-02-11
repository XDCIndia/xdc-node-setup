'use client';

import { useLayoutEffect, useRef } from 'react';
import * as am5 from '@amcharts/amcharts5';
import * as am5xy from '@amcharts/amcharts5/xy';
import * as am5radar from '@amcharts/amcharts5/radar';
import { HardDrive, Database, TrendingUp, Gauge, ArrowUpDown } from 'lucide-react';
import { XdcDarkTheme, colors } from '@/lib/amcharts-theme';
import { formatBytes, formatBytesPerSecond, formatNumber } from '@/lib/formatters';
import type { StorageData } from '@/lib/types';

interface StoragePanelProps {
  data: StorageData;
}

export default function StoragePanel({ data }: StoragePanelProps) {
  const growthRef = useRef<HTMLDivElement>(null);
  const gaugeRef = useRef<HTMLDivElement>(null);
  const ioRef = useRef<HTMLDivElement>(null);

  // Growth Chart
  useLayoutEffect(() => {
    if (!growthRef.current) return;

    const root = am5.Root.new(growthRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);

    const chart = root.container.children.push(
      am5xy.XYChart.new(root, {
        panX: false,
        panY: false,
        paddingLeft: 0,
      })
    );

    const chartData = Array.from({ length: 30 }, (_, i) => ({
      day: `${30 - i}d`,
      value: (data.chainDataSize || 100 * 1024 * 1024 * 1024) - (30 - i) * 1024 * 1024 * 1024 * 0.5,
    }));

    const xAxis = chart.xAxes.push(
      am5xy.CategoryAxis.new(root, {
        categoryField: 'day',
        renderer: am5xy.AxisRendererX.new(root, { minGridDistance: 40 }),
      })
    );
    xAxis.get('renderer').labels.template.setAll({
      fill: am5.color(colors.textSecondary),
      fontSize: 9,
    });
    xAxis.data.setAll(chartData);

    const yAxis = chart.yAxes.push(
      am5xy.ValueAxis.new(root, {
        renderer: am5xy.AxisRendererY.new(root, {}),
        numberFormat: "#.#a",
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
        categoryXField: 'day',
        stroke: am5.color(colors.purple),
        fill: am5.color(colors.purple),
      })
    );
    series.strokes.template.setAll({ strokeWidth: 2 });
    series.fills.template.setAll({ visible: true, fillOpacity: 0.2 });
    series.data.setAll(chartData);

    return () => root.dispose();
  }, [data.chainDataSize]);

  // Cache Gauge
  useLayoutEffect(() => {
    if (!gaugeRef.current) return;

    const root = am5.Root.new(gaugeRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);

    const chart = root.container.children.push(
      am5radar.RadarChart.new(root, {
        panX: false,
        panY: false,
        startAngle: -90,
        endAngle: 270,
        innerRadius: am5.percent(75),
      })
    );

    const axisRenderer = am5radar.AxisRendererCircular.new(root, {
      strokeOpacity: 0,
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

    // Background
    const range0 = xAxis.createAxisRange(xAxis.makeDataItem({ above: true, value: 0, endValue: 100 }));
    range0.get('axisFill')?.setAll({
      visible: true,
      fill: am5.color(colors.border),
      fillOpacity: 0.5,
    });

    // Progress
    const range1 = xAxis.createAxisRange(xAxis.makeDataItem({ above: true, value: 0, endValue: 0 }));
    range1.get('axisFill')?.setAll({
      visible: true,
      fill: am5.color(colors.success),
    });

    range1.animate({
      key: 'endValue',
      to: data.trieCacheHitRate,
      duration: 1000,
      easing: am5.ease.out(am5.ease.cubic),
    });

    // Center label
    chart.children.push(
      am5.Label.new(root, {
        text: `${Math.round(data.trieCacheHitRate)}%`,
        fontSize: 16,
        fontWeight: '700',
        fill: am5.color(colors.textPrimary),
        centerX: am5.percent(50),
        centerY: am5.percent(50),
        x: am5.percent(50),
        y: am5.percent(50),
      })
    );

    return () => root.dispose();
  }, [data.trieCacheHitRate]);

  // I/O Chart
  useLayoutEffect(() => {
    if (!ioRef.current) return;

    const root = am5.Root.new(ioRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);

    const chart = root.container.children.push(
      am5xy.XYChart.new(root, {
        panX: false,
        panY: false,
        paddingLeft: 0,
        paddingRight: 0,
      })
    );

    const now = Date.now();
    const chartData = Array.from({ length: 20 }, (_, i) => ({
      time: new Date(now - (19 - i) * 1000),
      read: Math.random() * 50 * 1024 * 1024,
      write: Math.random() * 30 * 1024 * 1024,
    }));

    const xAxis = chart.xAxes.push(
      am5xy.DateAxis.new(root, {
        baseInterval: { timeUnit: 'second', count: 1 },
        renderer: am5xy.AxisRendererX.new(root, {}),
      })
    );
    xAxis.get('renderer').labels.template.set('visible', false);

    const yAxis = chart.yAxes.push(
      am5xy.ValueAxis.new(root, {
        renderer: am5xy.AxisRendererY.new(root, {}),
        numberFormat: "#.#a",
      })
    );
    yAxis.get('renderer').labels.template.setAll({
      fill: am5.color(colors.textSecondary),
      fontSize: 10,
    });

    // Read series
    const readSeries = chart.series.push(
      am5xy.LineSeries.new(root, {
        name: 'Read',
        xAxis,
        yAxis,
        valueYField: 'read',
        valueXField: 'time',
        stroke: am5.color(colors.accent),
      })
    );
    readSeries.strokes.template.setAll({ strokeWidth: 2 });

    // Write series
    const writeSeries = chart.series.push(
      am5xy.LineSeries.new(root, {
        name: 'Write',
        xAxis,
        yAxis,
        valueYField: 'write',
        valueXField: 'time',
        stroke: am5.color(colors.success),
      })
    );
    writeSeries.strokes.template.setAll({ strokeWidth: 2 });

    readSeries.data.setAll(chartData);
    writeSeries.data.setAll(chartData);

    // Legend
    const legend = chart.children.push(am5.Legend.new(root, {
      centerX: am5.percent(50),
      x: am5.percent(50),
      y: 0,
    }));
    legend.labels.template.setAll({ fill: am5.color(colors.textSecondary), fontSize: 10 });
    legend.data.setAll(chart.series.values);

    return () => root.dispose();
  }, []);

  return (
    <div id="storage" className="card-premium p-4 sm:p-5">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#775DD0]/20 to-[#FF66C2]/20 flex items-center justify-center">
          <HardDrive className="w-5 h-5 text-[#775DD0]" />
        </div>
        <div>
          <h2 className="text-lg font-bold text-[#E8E8F0]">Storage &amp; Database</h2>
          <div className="text-sm text-[#8B8CA7]">Chain data &amp; I/O metrics</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        {/* Left Column */}
        <div className="space-y-4">
          {/* Chain Data Size */}
          <div className="p-4 rounded-xl bg-[#0B1120]/50">
            <div className="stat-label mb-2 flex items-center gap-1">
              <Database className="w-3 h-3" /> Chain Data Size
            </div>
            <div className="text-xl sm:text-2xl font-bold text-[#E8E8F0] mb-2">{formatBytes(data.chainDataSize)}</div>
            <div className="flex items-center gap-2 text-sm">
              <TrendingUp className="w-4 h-4 text-[#00E396]" />
              <span className="text-[#00E396]">~1.2 GB/day</span>
            </div>
          </div>

          {/* Growth Chart */}
          <div>
            <div className="stat-label mb-2">Growth Trend (30 days)</div>
            <div ref={growthRef} className="w-full h-[100px] sm:h-[120px]" />
          </div>
        </div>

        {/* Right Column */}
        <div className="space-y-4">
          {/* Cache Gauge + Compaction */}
          <div className="flex gap-4">
            <div className="w-1/2">
              <div ref={gaugeRef} className="w-full h-[100px] sm:h-[120px]" />
              <div className="text-center text-xs text-[#8B8CA7] -mt-2">Cache Hit</div>
            </div>

            <div className="w-1/2 space-y-3">
              <div className="p-3 rounded-xl bg-[#0B1120]/50">
                <div className="stat-label flex items-center gap-1">
                  <Gauge className="w-3 h-3" /> Cache Miss
                </div>
                <div className="stat-value text-[#FEB019]">{formatNumber(data.trieCacheMiss)}</div>
              </div>

              <div className="p-3 rounded-xl bg-[#0B1120]/50">
                <div className="stat-label">Compaction</div>
                <div className="stat-value text-[#E8E8F0]">{data.compactTime.toFixed(1)}s</div>
              </div>
            </div>
          </div>

          {/* I/O Activity */}
          <div>
            <div className="stat-label mb-2 flex items-center gap-1">
              <ArrowUpDown className="w-3 h-3" /> Disk I/O Activity
            </div>
            <div ref={ioRef} className="w-full h-[100px] sm:h-[120px]" />
          </div>
        </div>
      </div>
    </div>
  );
}
