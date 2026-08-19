import http from 'k6/http';
import { check, sleep } from 'k6';

const baseUrl = (__ENV.BASE_URL || '').replace(/\/$/, '');

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || '5m',
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  thresholds: {
    checks: ['rate==1'],
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(95)<2000'],
  },
};

export function setup() {
  if (!baseUrl) {
    throw new Error('BASE_URL is required');
  }
}

export default function () {
  const response = http.get(`${baseUrl}/api/products`, {
    tags: { drill: 'p11-4-node-loss' },
  });
  check(response, {
    'catalog returns HTTP 200': (result) => result.status === 200,
  });
  if (response.status !== 200) {
    console.error(JSON.stringify({
      event: 'catalog-request-failed',
      timestamp: new Date().toISOString(),
      status: response.status,
      errorCode: response.error_code || '',
      error: response.error || '',
      durationMs: response.timings.duration,
    }));
  }
  sleep(0.1);
}
