import http from '@ohos.net.http';
import { SessionStore } from './SessionStore';

/**
 * Central HTTP entry point for authenticated Trilium requests.
 *
 * 401 means the ETAPI token is no longer accepted, so the session is cleared
 * once here and the caller only has to handle the AUTH_401 error. Login/token
 * requests intentionally use http directly because a 401 there is a credential
 * failure, not an expired session.
 */
export class HttpService {
  static async request(url: string, options: http.HttpRequestOptions,
    clearOn401: boolean = true): Promise<http.HttpResponse> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, options);
      if (response.responseCode === 401) {
        if (clearOn401) {
          await SessionStore.clear();
        }
        throw new Error('AUTH_401');
      }
      return response;
    } finally {
      request.destroy();
    }
  }
}
