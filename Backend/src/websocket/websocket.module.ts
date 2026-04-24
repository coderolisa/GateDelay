import { Module } from '@nestjs/common';
import { PriceGateway } from './price.gateway';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  providers: [PriceGateway],
  exports: [PriceGateway],
})
export class WebsocketModule {}
