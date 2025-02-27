import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get_10101/common/application/channel_info_service.dart';
import 'package:get_10101/common/domain/channel.dart';
import 'package:get_10101/common/domain/model.dart';
import 'package:get_10101/common/fiat_input_form_field.dart';
import 'package:get_10101/common/value_data_row.dart';
import 'package:get_10101/features/stable/stable_dialog.dart';
import 'package:get_10101/features/stable/stable_value_change_notifier.dart';
import 'package:get_10101/features/trade/domain/direction.dart';
import 'package:get_10101/features/trade/domain/trade_values.dart';
import 'package:get_10101/features/trade/submit_order_change_notifier.dart';
import 'package:get_10101/features/wallet/domain/wallet_info.dart';
import 'package:get_10101/features/wallet/wallet_change_notifier.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

stableBottomSheet({required BuildContext context}) {
  showModalBottomSheet<void>(
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(20),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    isScrollControlled: true,
    useRootNavigator: true,
    context: context,
    builder: (BuildContext context) {
      return SafeArea(
          child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        // the GestureDetector ensures that we can close the keyboard by tapping into the modal
        child: GestureDetector(
          onTap: () {
            FocusScopeNode currentFocus = FocusScope.of(context);

            if (!currentFocus.hasPrimaryFocus) {
              currentFocus.unfocus();
            }
          },
          child: const SingleChildScrollView(
            child: SizedBox(
              // TODO: Find a way to make height dynamic depending on the children size
              // This is needed because otherwise the keyboard does not push the sheet up correctly
              height: 350,
              child: StableBottomSheet(),
            ),
          ),
        ),
      ));
    },
  );
}

class StableBottomSheet extends StatefulWidget {
  const StableBottomSheet({super.key});

  @override
  State<StableBottomSheet> createState() => _StableBottomSheet();
}

class _StableBottomSheet extends State<StableBottomSheet> {
  late final SubmitOrderChangeNotifier submitOrderChangeNotifier;

  late final TextEditingController quantityController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    submitOrderChangeNotifier = context.read<SubmitOrderChangeNotifier>();
    final stableValuesChangeNotifier = context.read<StableValuesChangeNotifier>();
    quantityController = TextEditingController(
        text: stableValuesChangeNotifier.stableValues().quantity!.ceil().toString());
    super.initState();
  }

  @override
  void dispose() {
    quantityController.dispose();
    super.dispose();
  }

  Future<(ChannelInfo?, Amount, Amount)> _getChannelInfo(
      ChannelInfoService channelInfoService) async {
    var channelInfo = await channelInfoService.getChannelInfo();

    /// The max channel capacity as received by the LSP or if there is an existing channel
    var lspMaxChannelCapacity = await channelInfoService.getMaxCapacity();

    /// The max channel capacity as received by the LSP or if there is an existing channel
    Amount tradeFeeReserve = await channelInfoService.getTradeFeeReserve();

    var completer = Completer<(ChannelInfo?, Amount, Amount)>();
    completer.complete((channelInfo, lspMaxChannelCapacity, tradeFeeReserve));

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final stableValuesChangeNotifier = context.watch<StableValuesChangeNotifier>();
    final tradeValues = stableValuesChangeNotifier.stableValues();
    tradeValues.direction = Direction.short;

    final ChannelInfoService channelInfoService = context.read<ChannelInfoService>();

    SubmitOrderChangeNotifier submitOrderChangeNotifier =
        context.watch<SubmitOrderChangeNotifier>();

    WalletInfo walletInfo = context.watch<WalletChangeNotifier>().walletInfo;

    if (submitOrderChangeNotifier.pendingOrder != null &&
        submitOrderChangeNotifier.pendingOrder!.state == PendingOrderState.submitting) {
      final pendingOrder = submitOrderChangeNotifier.pendingOrder;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        return await showDialog(
            context: context,
            useRootNavigator: true,
            barrierDismissible: false, // Prevent user from leaving
            builder: (BuildContext context) {
              return StableDialog(
                pendingOrder: pendingOrder!,
              );
            });
      });
    }

    final now = DateTime.now();

    return Form(
        key: _formKey,
        child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<(ChannelInfo?, Amount, Amount)>(
                  future: _getChannelInfo(channelInfoService),
                  // a previously-obtained Future<String> or null
                  builder: (BuildContext context,
                      AsyncSnapshot<(ChannelInfo?, Amount, Amount)> snapshot) {
                    if (!snapshot.hasData) {
                      return Container();
                    }

                    var (channelInfo, lspMaxChannelCapacity, tradeFeeReserve) = snapshot.data!;

                    Amount channelCapacity = lspMaxChannelCapacity;

                    Amount initialReserve = channelInfoService.getInitialReserve();

                    Amount channelReserve = channelInfo?.reserve ?? initialReserve;
                    int totalReserve = channelReserve.sats + tradeFeeReserve.sats;

                    int usableBalance = max(walletInfo.balances.lightning.sats - totalReserve, 0);
                    // the assumed balance of the counterparty based on the channel and our balance
                    // this is needed to make sure that the counterparty can fulfil the trade
                    int counterpartyUsableBalance = max(
                        channelCapacity.sats - (walletInfo.balances.lightning.sats + totalReserve),
                        0);

                    return Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            "How much do you want to stabilize?",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                  child: Selector<StableValuesChangeNotifier, double>(
                                      selector: (_, provider) =>
                                          provider.stableValues().quantity ?? 0.0,
                                      builder: (context, quantity, child) {
                                        return FiatAmountInputField(
                                          value: tradeValues.quantity!,
                                          hint: "e.g. 10 USD",
                                          label: "Quantity (USD)",
                                          controller: quantityController,
                                          onChanged: (value) {
                                            if (value.isEmpty) {
                                              stableValuesChangeNotifier.updateQuantity(0);
                                              return;
                                            }

                                            stableValuesChangeNotifier
                                                .updateQuantity(double.parse(value));
                                          },
                                          validator: (value) {
                                            if (value == null || value.isEmpty || value == "0") {
                                              return "Enter a quantity";
                                            }
                                            try {
                                              final quantity = double.parse(value);
                                              if (quantity < 1) {
                                                return "The minimum quantity is 1";
                                              }

                                              if (tradeValues.margin!.sats > usableBalance) {
                                                return "You don't have enough funds";
                                              }

                                              if (tradeValues.margin!.sats >
                                                  counterpartyUsableBalance) {
                                                return "Your counterparty does not have enough funds";
                                              }
                                            } catch (exception) {
                                              return "Enter a valid number";
                                            }
                                            return null;
                                          },
                                          isLoading: false,
                                        );
                                      })),
                            ],
                          ),
                          const SizedBox(height: 20.0),
                          ValueDataRow(
                              type: ValueType.amount,
                              value: tradeValues.margin,
                              label: "Costs in Sats",
                              valueTextStyle: const TextStyle(fontSize: 18),
                              labelTextStyle: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 16.0),
                          ValueDataRow(
                              type: ValueType.date,
                              value: DateTime.utc(now.year, now.month, now.day + 2).toLocal(),
                              label: "Expiry",
                              valueTextStyle: const TextStyle(fontSize: 18),
                              labelTextStyle: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 16.0),
                          ValueDataRow(
                              type: ValueType.amount,
                              value: tradeValues.fee,
                              label: "Fees",
                              valueTextStyle: const TextStyle(fontSize: 18),
                              labelTextStyle: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 20.0),
                          ElevatedButton(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  TradeValues tradeValues =
                                      stableValuesChangeNotifier.stableValues();

                                  final submitOrderChangeNotifier =
                                      context.read<SubmitOrderChangeNotifier>();
                                  submitOrderChangeNotifier.submitPendingOrder(
                                      tradeValues, PositionAction.open);

                                  GoRouter.of(context).pop();
                                }
                              },
                              child: const Text("Confirm")),
                        ],
                      ),
                    );
                  })
            ]));
  }
}
