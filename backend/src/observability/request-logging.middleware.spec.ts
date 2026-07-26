import { EventEmitter } from 'events';
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
});
