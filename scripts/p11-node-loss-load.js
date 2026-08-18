import http from 'k6/http';
import { check, sleep } from 'k6';

const baseUrl = (__ENV.BASE_URL || '').replace(/\/$/, '');

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || '5m',
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
  sleep(0.1);
}
