import { promises as fs } from 'fs';
import path from 'path';
import type { VersionConfig, Settings, AlertState } from './types';

const CONFIGS_DIR = path.join(process.cwd(), '..', 'configs');
const VAR_DIR = '/var/lib/xdc-node';

export async function getVersionConfig(): Promise<VersionConfig | null> {
  try {
    const filePath = path.join(CONFIGS_DIR, 'versions.json');
    const content = await fs.readFile(filePath, 'utf-8');
    return JSON.parse(content) as VersionConfig;
  } catch (error) {
    console.error('Error reading versions config:', error);
    return null;
  }
}

export async function saveVersionConfig(config: VersionConfig): Promise<boolean> {
  try {
    const filePath = path.join(CONFIGS_DIR, 'versions.json');
    await fs.writeFile(filePath, JSON.stringify(config, null, 2));
    return true;
  } catch (error) {
    console.error('Error saving versions config:', error);
    return false;
  }
}

export async function getAlertState(): Promise<AlertState | null> {
  try {
    const filePath = path.join(VAR_DIR, 'alert-state.json');
    const content = await fs.readFile(filePath, 'utf-8');
    return JSON.parse(content) as AlertState;
  } catch (error) {
    // Return empty state if file doesn't exist
    return {
      alerts: [],
      lastUpdated: new Date().toISOString()
    };
  }
}

export async function saveAlertState(state: AlertState): Promise<boolean> {
  try {
    const filePath = path.join(VAR_DIR, 'alert-state.json');
    await fs.mkdir(VAR_DIR, { recursive: true });
    await fs.writeFile(filePath, JSON.stringify(state, null, 2));
    return true;
  } catch (error) {
    console.error('Error saving alert state:', error);
    return false;
  }
}

export async function getSettings(): Promise<Settings> {
  try {
    const filePath = path.join(CONFIGS_DIR, 'dashboard-settings.json');
    const content = await fs.readFile(filePath, 'utf-8');
    return JSON.parse(content) as Settings;
  } catch (error) {
    // Return default settings
    return getDefaultSettings();
  }
}

export async function saveSettings(settings: Settings): Promise<boolean> {
  try {
    const filePath = path.join(CONFIGS_DIR, 'dashboard-settings.json');
    await fs.writeFile(filePath, JSON.stringify(settings, null, 2));
    return true;
  } catch (error) {
    console.error('Error saving settings:', error);
    return false;
  }
}

function getDefaultSettings(): Settings {
  return {
    notifications: {
      channels: [
        {
          type: 'telegram',
          enabled: false,
          config: { botToken: '', chatId: '' }
        }
      ],
      quietHours: {
        enabled: false,
        start: '22:00',
        end: '08:00',
        timezone: 'UTC'
      },
      digest: {
        enabled: false,
        frequency: 'daily',
        time: '09:00'
      },
      levels: {
        critical: true,
        warning: true,
        info: false
      }
    },
    nodes: [],
    apiKeys: [],
    theme: 'dark'
  };
}

export function validateApiKey(key: string, settings: Settings): boolean {
  const envKey = process.env.API_KEY;
  if (envKey && key === envKey) return true;
  
  return settings.apiKeys.some(k => k.key === key);
}
