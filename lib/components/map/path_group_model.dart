import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:festapp_core/map.dart';
import 'package:trina_grid/trina_grid.dart';

class PathGroupsModel extends ITrinaRowModel {
  static const String pathsOffline = "pathsOffline";
  static const String aggregateVersionColumn = TrinaRowVersion.column;

  @override
  int? id;
  String? title;
  Map<String, dynamic>? data;
  List<List<PathNode>>? pathData;
  String? color;
  bool? isHidden;
  int? icon;
  int? order; // new ordering field
  int aggregateVersion;

  PathGroupsModel({
    required this.id,
    this.title,
    this.data,
    this.pathData,
    this.color,
    this.isHidden,
    this.icon,
    this.order,
    this.aggregateVersion = 0,
  });

  /// Deserialize from server JSON
  factory PathGroupsModel.fromJson(Map<String, dynamic> json) {
    // parse JSON array-of-arrays into List<List<PathNode>>; each element is
    // either a bare number (place ref) or a {lat,lng} object (free point).
    final raw = json[Tb.path_groups.path_data] as List<dynamic>?;
    final pathData = raw
        ?.cast<List<dynamic>>()
        .map((sub) =>
            sub.map((n) => PathNode.fromJson(n)).whereType<PathNode>().toList())
        .toList();

    final data = json[Tb.path_groups.data] as Map<String, dynamic>?;
    final hidden = json[Tb.path_groups.is_hidden] as bool? ?? false;

    return PathGroupsModel(
      id: json[Tb.path_groups.id] as int?,
      title: json[Tb.path_groups.title] as String?,
      data: data,
      pathData: pathData,
      color: data?[Tb.path_groups.color] as String?,
      isHidden: hidden,
      icon: json[Tb.path_groups.icon] as int?,
      order: json[Tb.path_groups.order] as int?, // extract order
      aggregateVersion: TrinaRowVersion.read(json),
    );
  }

  /// Deserialize from Pluto JSON (cells), splitting on “;” then “,”
  static PathGroupsModel fromPlutoJson(Map<String, dynamic> json) {
    // build pathData from single CSV-with-sub‑CSV string. Each token is either
    // a place id (number) or a free point written as `@lat:lng`.
    final rawPlaces = (json[Tb.places.table]?.toString().trim() ?? "");
    final pathData = rawPlaces.isEmpty
        ? <List<PathNode>>[]
        : rawPlaces.split(';').map((segment) {
            final part = segment.trim();
            if (part.isEmpty) return <PathNode>[];
            return part
                .split(',')
                .map((s) => _parseCsvNode(s.trim()))
                .whereType<PathNode>()
                .toList();
          }).toList();

    // parse any JSON blob
    final rawData = (json[Tb.path_groups.data]?.toString().trim() ?? "");
    final parsedData = rawData.isNotEmpty
        ? jsonDecode(rawData) as Map<String, dynamic>
        : <String, dynamic>{};

    // override color if there’s a separate column
    final rawColor = json[Tb.path_groups.color]?.toString().trim();
    if (rawColor != null && rawColor.isNotEmpty) {
      parsedData[Tb.path_groups.color] = rawColor;
    }

    // parse hidden flag
    final rawHidden = json[Tb.path_groups.is_hidden];
    final hidden = rawHidden is bool
        ? rawHidden
        : (rawHidden?.toString().toLowerCase() == 'true');

    // parse icon (could come in as int or string)
    final rawIcon = json[Tb.path_groups.icon];
    int? icon;
    if (rawIcon is int) {
      icon = rawIcon;
    } else if (rawIcon != null && rawIcon.toString().isNotEmpty) {
      icon = int.tryParse(rawIcon.toString());
    }

    // parse order (could come in as int or string)
    final rawOrder = json[Tb.path_groups.order];
    int? order;
    if (rawOrder is int) {
      order = rawOrder;
    } else if (rawOrder != null && rawOrder.toString().isNotEmpty) {
      order = int.tryParse(rawOrder.toString());
    }

    return PathGroupsModel(
      id: json[Tb.path_groups.id] == -1
          ? null
          : json[Tb.path_groups.id] as int?,
      aggregateVersion: TrinaRowVersion.read(json),
      title: json[Tb.path_groups.title] as String?,
      data: parsedData,
      pathData: pathData,
      color: parsedData[Tb.path_groups.color] as String?,
      isHidden: hidden,
      icon: icon,
      order: order, // include order
    );
  }

  /// Serialize back to JSON
  Map<String, dynamic> toJson() => {
        Tb.path_groups.id: id,
        Tb.path_groups.title: title,
        Tb.path_groups.data: data,
        Tb.path_groups.is_hidden: isHidden,
        Tb.path_groups.path_data: pathData
            ?.map((seg) => seg.map((n) => n.toJson()).toList())
            .toList(),
        Tb.path_groups.icon: icon,
        Tb.path_groups.order: order, // add order
      };

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    // join each sub‑list with commas, then sub‑lists with semicolons. Place
    // refs render as their id, free points as `@lat:lng`.
    final placesCsv = pathDataToCsv(pathData);

    return TrinaRow(cells: {
      aggregateVersionColumn: TrinaRowVersion.cell(aggregateVersion),
      Tb.path_groups.id: TrinaCell(value: id),
      Tb.path_groups.title: TrinaCell(value: title),
      Tb.path_groups.data:
          TrinaCell(value: data != null ? jsonEncode(data) : ""),
      Tb.path_groups.color: TrinaCell(value: color ?? ""),
      Tb.path_groups.is_hidden: TrinaCell(value: isHidden.toString()),
      // Backing cell for the "Draw on map" button column. Not used for saving —
      // the drawn path is written back into the [Tb.places.table] CSV cell.
      Tb.path_groups.path_data: TrinaCell(value: placesCsv),
      Tb.places.table: TrinaCell(value: placesCsv),
      Tb.path_groups.icon: TrinaCell(value: icon),
      Tb.path_groups.order: TrinaCell(value: order), // include order cell
    });
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbPlaces.deletePathGroup(this);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbPlaces.updatePathGroup(this);
  }

  /// Parse one CSV token into a [PathNode]: `@lat:lng` → free point, otherwise
  /// an integer place id. Returns null for unparseable tokens.
  static PathNode? _parseCsvNode(String token) {
    if (token.isEmpty) return null;
    if (token.startsWith('@')) {
      final coords = token.substring(1).split(':');
      if (coords.length != 2) return null;
      final lat = double.tryParse(coords[0].trim());
      final lng = double.tryParse(coords[1].trim());
      if (lat == null || lng == null) return null;
      return PathNode.point(lat, lng);
    }
    final id = int.tryParse(token);
    return id == null ? null : PathNode.place(id);
  }

  /// Render one [PathNode] as a CSV token (inverse of [_parseCsvNode]).
  static String _nodeToCsv(PathNode node) =>
      node.isPoint ? '@${node.lat}:${node.lng}' : '${node.placeId}';

  /// Serialize `pathData` to the grid's CSV format: nodes joined by `,`,
  /// segments joined by `;`. This is the value the map drawing screen returns
  /// and that [fromPlutoJson] parses back.
  static String pathDataToCsv(List<List<PathNode>>? pathData) {
    if (pathData == null || pathData.isEmpty) return "";
    return pathData.map((sub) => sub.map(_nodeToCsv).join(',')).join(';');
  }

  @override
  String toBasicString() => title ?? '';
}
