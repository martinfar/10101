import 'package:f_logs/model/flog/flog.dart';
import 'package:flutter/material.dart';
import 'package:get_10101/bridge_generated/bridge_definitions.dart' as bridge;
import 'package:get_10101/common/application/event_service.dart';
import 'package:get_10101/common/domain/model.dart';
import 'package:get_10101/features/trade/application/position_service.dart';
import 'package:get_10101/features/trade/domain/contract_symbol.dart';
import 'package:get_10101/features/trade/domain/direction.dart';
import 'package:get_10101/features/trade/domain/leverage.dart';

import 'domain/position.dart';
import 'domain/price.dart';

class PositionChangeNotifier extends ChangeNotifier implements Subscriber {
  final PositionService _positionService;

  Map<ContractSymbol, Position> positions = {};

  Price? price;

  /// Amount of stabilised bitcoin in terms of USD (fiat)
  double getStableUSDAmountInFiat() {
    if (hasStableUSD()) {
      final positionUsd = positions[ContractSymbol.btcusd];
      return positionUsd!.quantity;
    } else {
      return 0.0;
    }
  }

  Amount getStableUSDAmountInSats() {
    if (hasStableUSD()) {
      final positionUsd = positions[ContractSymbol.btcusd];
      return positionUsd!.getAmountWithUnrealizedPnl();
    } else {
      return Amount(0);
    }
  }

  bool hasStableUSD() {
    final positionUsd = positions[ContractSymbol.btcusd];
    return positionUsd != null &&
        positionUsd.direction == Direction.short &&
        positionUsd.leverage == Leverage(1);
  }

  Future<void> initialize() async {
    List<Position> positions = await _positionService.fetchPositions();
    for (Position position in positions) {
      this.positions[position.contractSymbol] = position;
    }

    notifyListeners();
  }

  PositionChangeNotifier(this._positionService);

  @override
  void notify(bridge.Event event) {
    if (event is bridge.Event_PositionUpdateNotification) {
      Position position = Position.fromApi(event.field0);

      if (price != null) {
        final pnl = _positionService.calculatePnl(position, price!);
        position.unrealizedPnl = pnl != null ? Amount(pnl) : null;
      } else {
        position.unrealizedPnl = null;
      }
      positions[position.contractSymbol] = position;

      notifyListeners();
    } else if (event is bridge.Event_PositionClosedNotification) {
      ContractSymbol contractSymbol = ContractSymbol.fromApi(event.field0.contractSymbol);
      positions.remove(contractSymbol);

      notifyListeners();
    } else if (event is bridge.Event_PriceUpdateNotification) {
      price = Price.fromApi(event.field0);
      for (ContractSymbol symbol in positions.keys) {
        if (price != null) {
          if (positions[symbol] != null) {
            final pnl = _positionService.calculatePnl(positions[symbol]!, price!);
            positions[symbol]!.unrealizedPnl = pnl != null ? Amount(pnl) : null;
          }
        }
      }

      notifyListeners();
    } else {
      FLog.warning(text: "Received unexpected event: ${event.toString()}");
    }
  }
}
