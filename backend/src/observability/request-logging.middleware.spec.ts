import { EventEmitter } from 'events';
import { Logger } from '@nestjs/common';
import { RequestLoggingMiddleware } from './request-logging.middleware';

describe('RequestLoggingMiddleware', () => {
  it('propagates an incoming request id to the response header', () => {
    const middleware = new RequestLoggingMiddleware();
    const response = new EventEmitter() as EventEmitter & {
      statusCode: number;
      setHeader: jest.Mock;
    };
    response.statusCode = 200;
    response.setHeader = jest.fn();

    middleware.use(
      {
        method: 'GET',
        originalUrl: '/api/health',
        url: '/api/health',
        header: jest.fn().mockReturnValue('trace-123'),
      } as never,
      response as never,
      jest.fn(),
    );

    expect(response.setHeader).toHaveBeenCalledWith('x-request-id', 'trace-123');
  });

  it('logs the route template without capability values or query strings', () => {
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation();
    const middleware = new RequestLoggingMiddleware();
    const response = new EventEmitter() as EventEmitter & {
      statusCode: number;
      setHeader: jest.Mock;
    };
    response.statusCode = 200;
    response.setHeader = jest.fn();

    middleware.use(
      {
        method: 'GET',
        originalUrl: '/api/sessions/secret-session/invite?token=secret-token',
        url: '/api/sessions/secret-session/invite?token=secret-token',
        path: '/sessions/secret-session/invite',
        baseUrl: '/api',
        route: { path: '/sessions/:id/invite' },
        header: jest.fn(),
      } as never,
      response as never,
      jest.fn(),
    );
    response.emit('finish');

    const message = String(log.mock.calls[0][0]);
    expect(message).toContain('/api/sessions/:id/invite');
    expect(message).not.toContain('secret-session');
    expect(message).not.toContain('secret-token');
    log.mockRestore();
  });

  it('uses a sentinel instead of logging an unmatched capability path', () => {
    const warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation();
    const middleware = new RequestLoggingMiddleware();
    const response = new EventEmitter() as EventEmitter & {
      statusCode: number;
      setHeader: jest.Mock;
    };
    response.statusCode = 404;
    response.setHeader = jest.fn();

    middleware.use(
      {
        method: 'GET',
        path: '/invitations/secret-invite-code/typo',
        header: jest.fn(),
      } as never,
      response as never,
      jest.fn(),
    );
    response.emit('finish');

    const message = String(warn.mock.calls[0][0]);
    expect(message).toContain('"route":"unmatched"');
    expect(message).not.toContain('secret-invite-code');
    warn.mockRestore();
  });

  it('replaces an unsafe incoming request id before reflecting or logging it', () => {
    const log = jest.spyOn(Logger.prototype, 'log').mockImplementation();
    const middleware = new RequestLoggingMiddleware();
    const response = new EventEmitter() as EventEmitter & {
      statusCode: number;
      setHeader: jest.Mock;
    };
    response.statusCode = 200;
    response.setHeader = jest.fn();

    middleware.use(
      {
        method: 'GET',
        baseUrl: '/api',
        route: { path: '/health' },
        header: jest.fn().mockReturnValue('attacker\r\nforged-header: value'),
      } as never,
      response as never,
      jest.fn(),
    );
    response.emit('finish');

    const reflected = String(response.setHeader.mock.calls[0][1]);
    const message = String(log.mock.calls[0][0]);
    expect(reflected).toMatch(/^[0-9a-f-]{36}$/);
    expect(message).not.toContain('attacker');
    expect(message).not.toContain('forged-header');
    log.mockRestore();
  });
});
