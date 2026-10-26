import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';

const SOURCE_ROOT = join(__dirname, '..');

function productionSourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      return entry.name === 'dev' ? [] : productionSourceFiles(path);
    }
    if (!entry.name.endsWith('.ts') || entry.name.endsWith('.spec.ts')) {
      return [];
    }
    return [path];
  });
}

describe('production diagnostic safety', () => {
  it('does not interpolate sensitive values or raw provider errors into logs', () => {
    const forbidden = [
      /\.(?:message|stack)\b/,
      /response\.body\b/,
      /body\.slice\b/,
      /statusText\b/,
      /\$\{(?:e|err|error|exception)\b/,
      /\$\{[^}]*(?:String\((?:e|err|error|exception)\)|\.(?:name|place_name))\b/,
      /\$\{[^}]*\b(?:userId|sessionId|orderId|requesterId|hostId|reqId|friendUserId|restaurantId|paymentKey|objectPath|absoluteKeyPath|projectId|origin|phone|email|latitude|longitude|lat|lng)\b/,
      /(?:response|res|tossResponse)\?*\.[^}\s]*(?:message|body|statusText)\b/,
    ];
    const violations: string[] = [];

    for (const file of productionSourceFiles(SOURCE_ROOT)) {
      const source = readFileSync(file, 'utf8');
      const calls = source.match(
        /(?:(?:this\.)?logger|Logger)\.(?:log|warn|error|debug)\([\s\S]*?\);|console\.(?:log|warn|error|debug)\([\s\S]*?\);/g,
      );

      for (const call of calls ?? []) {
        for (const pattern of forbidden) {
          if (pattern.test(call)) {
            violations.push(`${file}: ${call.replace(/\s+/g, ' ')}`);
          }
        }
      }
    }

    expect(violations).toEqual([]);
  });

  it('does not expose raw upstream errors through HTTP exception messages', () => {
    const violations: string[] = [];

    for (const file of productionSourceFiles(SOURCE_ROOT)) {
      const source = readFileSync(file, 'utf8');
      const exceptions = source.match(
        /throw new (?:BadRequestException|ConflictException|ForbiddenException|InternalServerErrorException|NotFoundException|ServiceUnavailableException|UnauthorizedException|BadGatewayException)\([\s\S]*?\);/g,
      );

      for (const exception of exceptions ?? []) {
        if (
          /\.(?:message|stack)\b/.test(exception) ||
          /\b(?:tossResponse|uploadError|providerError|databaseError)\b/.test(
            exception,
          )
        ) {
          violations.push(`${file}: ${exception.replace(/\s+/g, ' ')}`);
        }
      }
    }

    expect(violations).toEqual([]);
  });
});
