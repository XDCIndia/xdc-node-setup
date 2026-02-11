/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  env: {
    PROMETHEUS_URL: process.env.PROMETHEUS_URL || 'http://127.0.0.1:19090',
    RPC_URL: process.env.RPC_URL || 'http://127.0.0.1:38545',
  },
};

export default nextConfig;
