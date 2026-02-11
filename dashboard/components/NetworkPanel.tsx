'use client';

import { useLayoutEffect, useRef } from 'react';
import * as am5 from '@amcharts/amcharts5';
import * as am5xy from '@amcharts/amcharts5/xy';
import * as am5radar from '@amcharts/amcharts5/radar';
import { XdcDarkTheme, colors } from '@/lib/amcharts-theme';
import { formatBytes, formatBytesPerSecond } from '@/lib/formatters';
import type { NetworkData } from '@/lib/types';

interface NetworkPanelProps {
  data: NetworkData;
}

export default function NetworkPanel({ data }: NetworkPanelProps) {
  const protocolRef = useRef<HTMLDivElement>(null);
  const bandwidthRef = useRef<HTMLDivElement>(null);
  const gaugeRef = useRef<HTMLDivElement>(null);

  // Protocol Traffic Bar Chart
  useLayoutEffect(() => {
    if (!protocolRef.current) return;

    const root = am5.Root.new(protocolRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);

    const chart = root.container.children.push(
      am5xy.XYChart.new(root, {
        panX: false,
        panY: false,
        paddingLeft: 0,
      })
    );

    const chartData = Array.from({ length: 12 }, (_, i) => ({
      time: `${12 - i}m`,
      eth100: data.eth100Traffic / 12 + Math.random() * 1000000,
      eth63: data.eth63Traffic / 12 + Math.random() * 500000,
    }));

    const xAxis = chart.xAxes.push(
      am5xy.CategoryAxis.new(root, {
        categoryField: 'time',
        renderer: am5xy.AxisRendererX.new(root, { minGridDistance: 30 }),
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

    // eth/100 series
    const series1 = chart.series.push(
      am5xy.ColumnSeries.new(root, {
        name: 'eth/100',
        xAxis,
        yAxis,
        valueYField: 'eth100',
        categoryXField: 'time',
        fill: am5.color(colors.accent),
        stacked: true,
      })
    );
    series1.columns.template.setAll({
      cornerRadiusTL: 0,
      cornerRadiusTR: 0,
      width: am5.percent(60),
    });

    // eth/63 series
    const series2 = chart.series.push(
      am5xy.ColumnSeries.new(root, {
        name: 'eth/63',
        xAxis,
        yAxis,
        valueYField: 'eth63',
        categoryXField: 'time',
        fill: am5.color(colors.accentLight),
        stacked: true,
      })
    );
    series2.columns.template.setAll({
      cornerRadiusTL: 4,
      cornerRadiusTR: 4,
      width: am5.percent(60),
    });

    series1.data.setAll(chartData);
    series2.data.setAll(chartData);

    // Legend
    const legend = chart.children.push(am5.Legend.new(root, {
      centerX: am5.percent(50),
      x: am5.percent(50),
      y: 0,
    }));
    legend.labels.template.setAll({ fill: am5.color(colors.textSecondary), fontSize: 10 });
    legend.data.setAll(chart.series.values);

    return () => root.dispose();
  }, [data]);

  // Bandwidth Chart
  useLayoutEffect(() => {
    if (!bandwidthRef.current) return;

    const root = am5.Root.new(bandwidthRef.current);
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
      inbound: data.inboundTraffic + Math.random() * 1000000,
      outbound: data.outboundTraffic + Math.random() * 500000,
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

    // Inbound series
    const inSeries = chart.series.push(
      am5xy.LineSeries.new(root, {
        name: 'Inbound',
        xAxis,
        yAxis,
        valueYField: 'inbound',
        valueXField: 'time',
        stroke: am5.color(colors.success),
        fill: am5.color(colors.success),
      })
    );
    inSeries.strokes.template.setAll({ strokeWidth: 2 });
    inSeries.fills.template.setAll({ visible: true, fillOpacity: 0.2 });

    // Outbound series
    const outSeries = chart.series.push(
      am5xy.LineSeries.new(root, {
        name: 'Outbound',
        xAxis,
        yAxis,
        valueYField: 'outbound',
        valueXField: 'time',
        stroke: am5.color(colors.accent),
        fill: am5.color(colors.accent),
      })
    );
    outSeries.strokes.template.setAll({ strokeWidth: 2 });
    outSeries.fills.template.setAll({ visible: true, fillOpacity: 0.2 });

    inSeries.data.setAll(chartData);
    outSeries.data.setAll(chartData);

    // Legend
    const legend = chart.children.push(am5.Legend.new(root, {
      centerX: am5.percent(50),
      x: am5.percent(50),
      y: 0,
    }));
    legend.labels.template.setAll({ fill: am5.color(colors.textSecondary), fontSize: 10 });
    legend.data.setAll(chart.series.values);

    return () => root.dispose();
  }, [data]);

  // Dial Success Gauge
  useLayoutEffect(() => {
    if (!gaugeRef.current) return;

    const root = am5.Root.new(gaugeRef.current);
    root.setThemes([XdcDarkTheme.new(root)]);

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

    const dialPercent = Math.round((data.dialSuccess / (data.dialTotal || 1)) * 100);
    const gaugeColor = dialPercent >= 80 ? colors.success : dialPercent >= 50 ? colors.warning : colors.error;

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
      fill: am5.color(gaugeColor),
    });

    range1.animate({
      key: 'endValue',
      to: dialPercent,
      duration: 1000,
      easing: am5.ease.out(am5.ease.cubic),
    });

    // Center label
    chart.children.push(
      am5.Label.new(root, {
        text: `${dialPercent}%`,
        fontSize: 16,
        fontWeight: '700',
        fill: am5.color(colors.textPrimary),
        centerX: am5.percent(50),
        centerY: am5.percent(80),
        x: am5.percent(50),
        y: am5.percent(50),
      })
    );

    return () => root.dispose();
  }, [data]);

  return (
    <div className="card-premium p-5">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#00E396]/20 flex items-center justify-center">
          <svg className="w-5 h-5 text-[#1E90FF]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
          </svg>
        </div>
        <div>
          <h2 className="text-lg font-bold text-[#E8E8F0]">Network Traffic</h2>
          <div className="text-sm text-[#8B8CA7]">Protocol & bandwidth metrics</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Protocol Traffic */}
        <div className="lg:col-span-2">
          <div className="stat-label mb-2">Protocol Traffic (eth/100 vs eth/63)</div>
          <div ref={protocolRef} style={{ width: '100%', height: '160px' }} />
        </div>

        {/* Stats */}
        <div className="space-y-4">
          <div className="flex gap-3">
            <div className="w-1/2">
              <div ref={gaugeRef} style={{ width: '100%', height: '90px' }} />
              <div className="text-center text-xs text-[#8B8CA7] -mt-1">Dial Success</div>
            </div>

            <div className="w-1/2 space-y-2">
              <div className="p-2 rounded-xl bg-[#0B1120]/50 text-center">
                <div className="text-xs text-[#8B8CA7]">Conn Errors</div>
                <div className="text-lg font-bold text-[#FF4560]">{data.connectionErrors}</div>
              </div>

              <div className="p-2 rounded-xl bg-[#0B1120]/50 text-center">
                <div className="text-xs text-[#8B8CA7]">Total Peers</div>
                <div className="text-lg font-bold text-[#1E90FF]">{data.totalPeers}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Bandwidth Chart */}
      <div className="mt-4">
        <div className="stat-label mb-2">Bandwidth Usage (Inbound vs Outbound)</div>
        <div ref={bandwidthRef} style={{ width: '100%', height: '120px' }} />
      </div>
    </div>
  );
}
