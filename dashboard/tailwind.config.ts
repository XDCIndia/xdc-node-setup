import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        card: {
          DEFAULT: "var(--card)",
          border: "var(--card-border)",
        },
        primary: {
          DEFAULT: "#1E90FF",
          dark: "#1873CC",
          light: "#4BA6FF",
        },
        success: "#00ff88",
        warning: "#ffaa00",
        error: "#ff4444",
        xdc: {
          bg: "#0a0a1a",
          card: "#151530",
          border: "#2a2a50",
          blue: "#1E90FF",
        },
      },
      animation: {
        "spin-slow": "spin 3s linear infinite",
        pulse: "pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite",
      },
      backdropBlur: {
        xs: "2px",
      },
    },
  },
  plugins: [],
};

export default config;
