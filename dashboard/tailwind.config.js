/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        xdc: {
          primary: '#1F4CED',
          secondary: '#3D6BF5',
          dark: '#0a0a0f',
          card: '#1a1a2e',
          border: '#2a2a3e',
        },
        status: {
          healthy: '#10B981',
          warning: '#F59E0B',
          critical: '#EF4444',
          info: '#3B82F6',
        }
      },
      fontFamily: {
        sans: ['Fira Sans', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
