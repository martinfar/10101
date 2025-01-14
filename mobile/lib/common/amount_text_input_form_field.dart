import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain/model.dart';
import 'modal_bottom_sheet_info.dart';

class AmountInputField extends StatefulWidget {
  const AmountInputField(
      {super.key,
      required this.controller,
      required this.label,
      required this.hint,
      required this.onChanged,
      required this.value,
      required this.isLoading,
      this.infoText,
      this.validator});

  final Amount value;
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? infoText;
  final bool isLoading;
  final Function(String) onChanged;

  final String? Function(String?)? validator;

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  @override
  Widget build(BuildContext context) {
    String value = widget.value.sats.toString();

    if (value.endsWith(".0")) {
      value = value.replaceAll(".0", "");
    }

    int offset = widget.controller.selection.base.offset;
    if (offset > value.length) {
      offset = value.length;
    }

    widget.controller.value = widget.controller.value.copyWith(
      text: value.toString(),
      selection: TextSelection.collapsed(offset: offset),
    );

    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hint,
        labelText: widget.label,
        suffixIcon: widget.isLoading
            ? const CircularProgressIndicator()
            : widget.infoText != null
                ? ModalBottomSheetInfo(closeButtonText: "Back...", child: Text(widget.infoText!))
                : null,
      ),
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) => widget.onChanged(value),
      validator: (value) {
        if (widget.validator != null) {
          return widget.validator!(value);
        }

        return null;
      },
    );
  }
}
