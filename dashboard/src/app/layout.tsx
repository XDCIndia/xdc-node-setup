import type { Metadata } from 'next';
import './globals.css';
import Sidebar from '@/components/Sidebar';

export const metadata: Metadata = {
  title: 'XDC Node Dashboard',
  description: 'Web dashboard for XDC Network node monitoring and management',
  icons: {
    icon: '/favicon.ico',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="bg-xdc-dark min-h-screen">
        <Sidebar />
        <main className="ml-64 p-6 min-h-screen">
          {children}
        </main>
      </body>
    </html>
  );
}
