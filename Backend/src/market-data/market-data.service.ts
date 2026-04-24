import { Injectable, Logger, Inject } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import type { Cache } from 'cache-manager';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { firstValueFrom } from 'rxjs';

const CACHE_TTL = 300; // 5 minutes
const FLIGHTS_CACHE_KEY = 'flights:all';

@Injectable()
export class MarketDataService {
  private readonly logger = new Logger(MarketDataService.name);
  private readonly apiKey: string;
  private readonly baseUrl = 'http://api.aviationstack.com/v1';

  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
    @Inject(CACHE_MANAGER) private readonly cacheManager: Cache,
  ) {
    this.apiKey = this.configService.get<string>('AVIATION_STACK_API_KEY', '');
  }

  async getFlights(params: {
    flightStatus?: string;
    airline?: string;
    flightNumber?: string;
    limit?: number;
    offset?: number;
  }) {
    const cacheKey = `flights:${JSON.stringify(params)}`;
    const cached = await this.cacheManager.get(cacheKey);
    if (cached) return cached;

    const data = await this.fetchFromAviationStack('/flights', {
      flight_status: params.flightStatus,
      airline_name: params.airline,
      flight_iata: params.flightNumber,
      limit: params.limit ?? 20,
      offset: params.offset ?? 0,
    });

    await this.cacheManager.set(cacheKey, data, CACHE_TTL * 1000);
    return data;
  }

  async getFlightByIata(iata: string) {
    const cacheKey = `flight:${iata}`;
    const cached = await this.cacheManager.get(cacheKey);
    if (cached) return cached;

    const data = await this.fetchFromAviationStack('/flights', {
      flight_iata: iata,
      limit: 1,
    });

    await this.cacheManager.set(cacheKey, data, CACHE_TTL * 1000);
    return data;
  }

  async getAirlines(params: { search?: string; limit?: number }) {
    const cacheKey = `airlines:${JSON.stringify(params)}`;
    const cached = await this.cacheManager.get(cacheKey);
    if (cached) return cached;

    const data = await this.fetchFromAviationStack('/airlines', {
      search: params.search,
      limit: params.limit ?? 20,
    });

    await this.cacheManager.set(cacheKey, data, CACHE_TTL * 1000);
    return data;
  }

  @Cron(CronExpression.EVERY_5_MINUTES)
  async refreshFlightData() {
    this.logger.log('Refreshing flight data cache...');
    try {
      const data = await this.fetchFromAviationStack('/flights', {
        flight_status: 'active',
        limit: 100,
      });
      await this.cacheManager.set(FLIGHTS_CACHE_KEY, data, CACHE_TTL * 1000);
      this.logger.log('Flight data cache refreshed');
    } catch (err) {
      this.logger.error('Failed to refresh flight data', err);
    }
  }

  private async fetchFromAviationStack(
    endpoint: string,
    params: Record<string, unknown>,
  ) {
    const cleanParams = Object.fromEntries(
      Object.entries({ ...params, access_key: this.apiKey }).filter(
        ([, v]) => v !== undefined && v !== null && v !== '',
      ),
    );

    const response = await firstValueFrom(
      this.httpService.get(`${this.baseUrl}${endpoint}`, {
        params: cleanParams,
        timeout: 10000,
      }),
    );
    return response.data;
  }
}
