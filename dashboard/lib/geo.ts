interface GeoResult {
  ip: string;
  lat: number;
  lon: number;
  country: string;
  countryCode: string;
  city: string;
  isp: string;
}

const geoCache = new Map<string, GeoResult>();

export async function geolocateIP(ip: string): Promise<GeoResult | null> {
  if (geoCache.has(ip)) return geoCache.get(ip)!;
  try {
    const res = await fetch(`http://ip-api.com/json/${ip}?fields=status,country,countryCode,city,lat,lon,isp`, {
      signal: AbortSignal.timeout(3000),
    });
    const data = await res.json();
    if (data.status === 'success') {
      const result = { ip, lat: data.lat, lon: data.lon, country: data.country, countryCode: data.countryCode, city: data.city, isp: data.isp };
      geoCache.set(ip, result);
      return result;
    }
  } catch {}
  return null;
}

// Batch: ip-api.com supports batch of up to 100
export async function geolocateBatch(ips: string[]): Promise<Map<string, GeoResult>> {
  const uncached = ips.filter(ip => !geoCache.has(ip));
  if (uncached.length > 0) {
    try {
      const res = await fetch('http://ip-api.com/batch?fields=status,query,country,countryCode,city,lat,lon,isp', {
        method: 'POST',
        body: JSON.stringify(uncached.map(ip => ({ query: ip }))),
        signal: AbortSignal.timeout(5000),
      });
      const results = await res.json();
      for (const r of results) {
        if (r.status === 'success') {
          geoCache.set(r.query, { ip: r.query, lat: r.lat, lon: r.lon, country: r.country, countryCode: r.countryCode, city: r.city, isp: r.isp });
        }
      }
    } catch {}
  }
  const result = new Map<string, GeoResult>();
  for (const ip of ips) {
    if (geoCache.has(ip)) result.set(ip, geoCache.get(ip)!);
  }
  return result;
}
