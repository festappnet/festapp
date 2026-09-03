import 'package:collection/collection.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/html/html_editor_page.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/custom_three_state_checkbox.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:trina_grid/trina_grid.dart';

import 'package:fstapp/components/_shared/common_strings.dart';

class DataGridHelper {
  static Widget buildHtmlEditorButton({
    required BuildContext context,
    required String field,
    required TrinaColumnRendererContext rendererContext,
    required Future<String?> Function()
        loadContent, // Used for both editor and potentially tooltip
    bool showTooltipWithContent = true,
    int? occasionId,
    String? title,
  }) {
    String? textToEdit = rendererContext.row.cells[field]?.value as String?;

    Widget buttonChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.edit),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(CommonStrings.edit),
        ),
      ],
    );

    Widget button = ElevatedButton(
      onPressed: () async {
        Map<String, dynamic> param = {
          HtmlEditorPage.parContent: textToEdit,
          HtmlEditorPage.parLoad: loadContent,
        };

        RouterService.navigatePageInfo(context,
                HtmlEditorRoute(content: param, occasionId: occasionId))
            .then((value) async {
          if (value != null) {
            var newText = value as String;
            // Compare with the value that was in the cell when edit was initiated
            if (newText != textToEdit) {
              rendererContext.row.cells[field]?.value = newText;
              var cell = rendererContext.row.cells[field]!;
              rendererContext.stateManager
                  .changeCellValue(cell, cell.value, force: true);
            }
          }
        });
      },
      child: buttonChild,
    );

    if (showTooltipWithContent) {
      final tooltipTheme = TooltipTheme.of(context);
      final effectiveDecoration = tooltipTheme.decoration ??
          BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[700]
                : Colors.white,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: Colors.grey.shade400, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          );
      final baseTextStyle =
          tooltipTheme.textStyle ?? DefaultTextStyle.of(context).style;
      final effectiveTextStyle = baseTextStyle.copyWith(fontSize: 14);

      return Tooltip(
        showDuration: const Duration(seconds: 15),
        preferBelow: true,
        verticalOffset: 52,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: EdgeInsets.zero,
        decoration: const BoxDecoration(color: Colors.transparent),
        richMessage: WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: FutureBuilder<String?>(
            future: loadContent(),
            builder: (context, snapshot) {
              Widget? titleWidget;
              if (title != null && title.isNotEmpty) {
                titleWidget = Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    title,
                    style: effectiveTextStyle.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: (effectiveTextStyle.fontSize ?? 14.0) +
                          2, // Slightly larger for title
                    ),
                    textAlign: TextAlign.start,
                  ),
                );
              }

              Widget mainContentArea;
              if (snapshot.connectionState == ConnectionState.waiting) {
                mainContentArea = const Center(
                    child: CircularProgressIndicator(strokeWidth: 2));
              } else if (snapshot.hasError ||
                  HtmlHelper.isHtmlEmptyOrNull(snapshot.data)) {
                mainContentArea = Center(
                  child: Icon(
                    Icons.text_snippet_outlined,
                    size: 22,
                    color: (effectiveTextStyle.color ?? Colors.grey)
                        .withOpacity(0.5),
                  ),
                );
              } else {
                final htmlContent = snapshot.data!;
                mainContentArea = SingleChildScrollView(
                  child: HtmlView(
                    html: htmlContent,
                    fontSize: effectiveTextStyle.fontSize!,
                    color: effectiveTextStyle.color,
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.all(
                    10.0), // Overall padding for the tooltip content
                constraints:
                    const BoxConstraints(maxWidth: 450, maxHeight: 300),
                decoration: effectiveDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment
                      .stretch, // Make title stretch if it's multi-line
                  mainAxisSize: MainAxisSize
                      .min, // Let column be as tall as needed, up to constraints
                  children: [
                    if (titleWidget != null) titleWidget,
                    Expanded(
                        child:
                            mainContentArea), // Main content takes remaining space
                  ],
                ),
              );
            },
          ),
        ),
        child: button,
      );
    }
    return button;
  }

  static Widget buildTab(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: ThemeConfig.blackColor(context)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            text,
            style: TextStyle(color: ThemeConfig.blackColor(context)),
          ),
        ),
      ],
    );
  }

  static T? getValueOrNull<T>(dynamic value, {T? emptyValue}) {
    if (value == emptyValue || value == "") return null;
    if (value is String) return value.trim() as T;
    return value as T?;
  }

  static String getValueFromFormatted(dynamic value) {
    final startIndex = value.indexOf(":");
    if (startIndex == -1) {
      return value;
    }
    var result = value.substring(startIndex + 1);
    return result;
  }

  static String returnQuestionMarkOnInvalid(
      dynamic value, List<String> allValues) {
    if (!allValues.contains(value)) {
      return "???";
    }
    return UserInfoModel.sexToLocale(value);
  }

  static int? getIdFromFormatted(String value) {
    final startIndex = value.indexOf(":");
    if (startIndex == -1) {
      return null;
    }
    var result = value.substring(0, startIndex);
    var res = int.parse(result);
    return res;
  }

  static Checkbox checkBoxRenderer(
      TrinaColumnRendererContext rendererContext, String idString,
      [bool Function()? isEnabled]) {
    var value = rendererContext.cell.value == "true" ? true : false;
    return Checkbox(
      value: value,
      onChanged: isEnabled != null && isEnabled() == false
          ? null
          : (bool? value) {
              var cell = rendererContext.row.cells[idString]!;
              rendererContext.stateManager
                  .changeCellValue(cell, value.toString(), force: true);
              rendererContext.cell.value = value.toString();
            },
    );
  }

  static Widget foodCheckBoxRenderer(rendererContext, String idString,
      [bool Function()? isEnabled]) {
    // Get the current state (default to "none" if the value is null or invalid)
    String currentState = rendererContext.cell.value ?? DbOccasions.serviceNone;

    return CustomThreeStateCheckbox(
      noneStateIcon: Icons.close,
      paidStateIcon: Icons.radio_button_checked,
      usedStateIcon: Icons.radio_button_off,
      currentState: currentState,
      onStateChanged: (String newState) {
        var cell = rendererContext.row.cells[idString]!;
        rendererContext.stateManager
            .changeCellValue(cell, newState, force: true);
        rendererContext.cell.value = newState;
        rendererContext.stateManager.notifyListeners();
      },
      isEnabled: isEnabled == null || isEnabled(),
    );
  }

  static Widget backgroundFromText(
      rendererContext, Color Function(String) getBackground,
      [Function(String)? processText]) {
    String value = rendererContext.cell.value;
    String textValue = processText?.call(value);
    return Container(
        color: getBackground(value), child: Center(child: Text(textValue)));
  }

  static Widget orderState(
      BuildContext context,
      TrinaColumnRendererContext rendererContext,
      Color Function(String) getBackground,
      [Function(String)? processText]) {
    String value = rendererContext.cell.value;
    String firstPart = value.split(";")[0];
    String textValue = processText?.call(value) ?? value;

    return Container(
      color: getBackground(value),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              textValue,
            ),
            if (firstPart == OrderModel.expiredState)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Tooltip(
                  message: 'Expired Order',
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: ThemeConfig.redColor(context),
                    child: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget orderStateRenderer(
      BuildContext context,
      TrinaColumnRendererContext rendererContext,
      Color Function(String) getBackground) {
    String value = rendererContext.cell.value;

    // A helper to create a single colored state tag
    Widget buildStateTag(String formattedState) {
      final key = formattedState.split(";").first;
      final text = formattedState.split(";").last;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: getBackground(key),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          OrderModel.statesDataGridToUpper(text),
        ),
      );
    }

    // Check if this is a state transition
    if (value.contains("→")) {
      final parts = value.split("→");
      final fromState = parts[0].trim();
      final toState = parts[1].trim();
      return Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            buildStateTag(fromState),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(Icons.arrow_forward, size: 18),
            ),
            buildStateTag(toState),
          ],
        ),
      );
    }
    // Otherwise, render a single state
    else {
      return Container(
        color: getBackground(value.split(";").first),
        child: Center(
            child:
                Text(OrderModel.statesDataGridToUpper(value.split(";").last))),
      );
    }
  }

  static Widget mapIconRenderer(
      BuildContext context, rendererContext, List<IconModel> icons) {
    int? value = rendererContext.cell.value;
    return iconToRow(context, value, icons);
  }

  static Widget iconToRow(
      BuildContext context, int? id, List<IconModel> icons) {
    final icon = icons.firstWhereOrNull((candidate) => candidate.id == id);
    final svgData = icon?.renderableSvgData;
    final label = icon?.displayLabel ?? IconModel.missingLabel;

    if (svgData != null) {
      var svgIcon = SizedBox(
        width: 20,
        height: 20,
        child: SvgPicture.string(
          svgData,
          colorFilter: ColorFilter.mode(
              ThemeConfig.blackColor(context), BlendMode.srcIn),
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.image_not_supported),
        ),
      );

      return Row(
        children: [
          svgIcon,
          const SizedBox(width: 12),
          Text(label),
        ],
      );
    }

    return Text(label);
  }

  static Widget idRenderer(rendererContext) {
    var value = rendererContext.cell.value == -1
        ? ""
        : rendererContext.cell.value.toString();
    return Text(value);
  }

  static TrinaGridLocaleText getPlutoLocaleFromLangCode(String langCode) {
    switch (langCode) {
      case "cs":
        return const TrinaGridLocaleText.czech();
      case "de":
        return const TrinaGridLocaleText.german();
      case "sk":
        return const TrinaGridLocaleText(
          // Column menu
          unfreezeColumn: 'Odomknúť stĺpec',
          freezeColumnToStart: 'Zmraziť stĺpec na začiatok',
          freezeColumnToEnd: 'Zmraziť stĺpec na koniec',
          autoFitColumn: 'Automaticky prispôsobiť stĺpec',
          hideColumn: 'Skryť stĺpec',
          setColumns: 'Nastaviť stĺpce',
          setFilter: 'Nastaviť filter',
          resetFilter: 'Obnoviť filter',
          // SetColumns popup
          setColumnsTitle: 'Názov stĺpca',
          // Filter popup
          filterColumn: 'Stĺpec',
          filterType: 'Typ',
          filterValue: 'Hodnota',
          filterAllColumns: 'Všetky stĺpce',
          filterContains: 'Obsahuje',
          filterEquals: 'Rovná sa',
          filterStartsWith: 'Začína na',
          filterEndsWith: 'Končí na',
          filterGreaterThan: 'Väčšie ako',
          filterGreaterThanOrEqualTo: 'Väčšie alebo rovné',
          filterLessThan: 'Menšie ako',
          filterLessThanOrEqualTo: 'Menšie alebo rovné',
          // Date popup
          sunday: 'Ne',
          monday: 'Po',
          tuesday: 'Ut',
          wednesday: 'St',
          thursday: 'Št',
          friday: 'Pia',
          saturday: 'So',
          // Time column popup
          hour: 'Hodina',
          minute: 'Minúta',
          // Common
          loadingText: 'Načíta sa',
        );
      case "pl":
        return const TrinaGridLocaleText(
          // Column menu
          unfreezeColumn: 'Odblokuj kolumnę',
          freezeColumnToStart: 'Zamroź kolumnę na początku',
          freezeColumnToEnd: 'Zamroź kolumnę na końcu',
          autoFitColumn: 'Dopasuj kolumnę automatycznie',
          hideColumn: 'Ukryj kolumnę',
          setColumns: 'Ustaw kolumny',
          setFilter: 'Ustaw filtr',
          resetFilter: 'Resetuj filtr',
          // SetColumns popup
          setColumnsTitle: 'Nazwa kolumny',
          // Filter popup
          filterColumn: 'Kolumna',
          filterType: 'Typ',
          filterValue: 'Wartość',
          filterAllColumns: 'Wszystkie kolumny',
          filterContains: 'Zawiera',
          filterEquals: 'Równa się',
          filterStartsWith: 'Zaczyna się od',
          filterEndsWith: 'Kończy się na',
          filterGreaterThan: 'Większa niż',
          filterGreaterThanOrEqualTo: 'Większa lub równa',
          filterLessThan: 'Mniejsza niż',
          filterLessThanOrEqualTo: 'Mniejsza lub równa',
          // Date popup
          sunday: 'Ni',
          monday: 'Po',
          tuesday: 'Wt',
          wednesday: 'Śr',
          thursday: 'Cz',
          friday: 'Pi',
          saturday: 'So',
          // Time column popup
          hour: 'Godzina',
          minute: 'Minuta',
          // Common
          loadingText: 'Ładowanie',
        );
      case "uk":
        return const TrinaGridLocaleText(
          unfreezeColumn: 'Розблокувати стовпець',
          freezeColumnToStart: 'Заморозити стовпець на початок',
          freezeColumnToEnd: 'Заморозити стовпець на кінець',
          autoFitColumn: 'Автоматично підлаштувати стовпець',
          hideColumn: 'Сховати стовпець',
          setColumns: 'Налаштувати стовпці',
          setFilter: 'Налаштувати фільтр',
          resetFilter: 'Скинути фільтр',
          setColumnsTitle: 'Назва стовпця',
          filterColumn: 'Стовпець',
          filterType: 'Тип',
          filterValue: 'Значення',
          filterAllColumns: 'Всі стовпці',
          filterContains: 'Містить',
          filterEquals: 'Дорівнює',
          filterStartsWith: 'Починається з',
          filterEndsWith: 'Закінчується на',
          filterGreaterThan: 'Більше ніж',
          filterGreaterThanOrEqualTo: 'Більше або дорівнює',
          filterLessThan: 'Менше ніж',
          filterLessThanOrEqualTo: 'Менше або дорівнює',
          sunday: 'Нд',
          monday: 'Пн',
          tuesday: 'Вт',
          wednesday: 'Ср',
          thursday: 'Чт',
          friday: 'Пт',
          saturday: 'Сб',
          hour: 'Година',
          minute: 'Хвилина',
          loadingText: 'Завантажується',
        );
    }

    return const TrinaGridLocaleText();
  }

  static String textTransform(String? value, List<String> allValues,
      String Function(String?) transform) {
    if (!allValues.contains(value)) {
      return "???";
    }
    return transform(value);
  }
}
