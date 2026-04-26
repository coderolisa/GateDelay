import { Module } from '@nestjs/common';
import { MarketResolverService } from './market-resolver.service';

@Module({
  providers: [MarketResolverService],
  exports: [MarketResolverService],
})
export class MarketsModule {}
