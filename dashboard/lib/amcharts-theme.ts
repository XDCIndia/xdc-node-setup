import * as am5 from '@amcharts/amcharts5';
import am5themes_Dark from '@amcharts/amcharts5/themes/Dark';

// XDC Dashboard Color Palette
export const colors = {
  bgBody: '#0B1120',
  bgCard: '#1a2035',
  bgCardHover: '#1e2642',
  border: '#2a3352',
  accent: '#1E90FF',
  accentLight: '#00D4FF',
  success: '#00E396',
  warning: '#FEB019',
  error: '#FF4560',
  purple: '#775DD0',
  pink: '#FF66C2',
  textPrimary: '#E8E8F0',
  textSecondary: '#8B8CA7',
};

// Color palette for charts
export const chartColors = [
  am5.color(colors.accent),
  am5.color(colors.success),
  am5.color(colors.warning),
  am5.color(colors.error),
  am5.color(colors.purple),
  am5.color(colors.accentLight),
  am5.color(colors.pink),
];

// Custom XDC Dark Theme
export class XdcDarkTheme extends am5themes_Dark {
  setupDefaultRules() {
    super.setupDefaultRules();

    // Root settings
    this.rule('ColorSet').setAll({
      colors: chartColors,
      step: 1,
    });

    // Label styling
    this.rule('Label').setAll({
      fill: am5.color(colors.textSecondary),
      fontSize: 12,
    });

    // Grid styling
    this.rule('Grid').setAll({
      stroke: am5.color(colors.border),
      strokeOpacity: 0.5,
    });
  }
}

// Helper to create a root with XDC theme
export function createAmChartsRoot(elementId: string): am5.Root {
  const root = am5.Root.new(elementId);
  root.setThemes([XdcDarkTheme.new(root)]);
  return root;
}

// Gradient helper
export function createGradient(root: am5.Root, startColor: string, endColor: string) {
  return am5.LinearGradient.new(root, {
    stops: [
      { color: am5.color(startColor) },
      { color: am5.color(endColor) },
    ],
  });
}
