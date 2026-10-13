import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/utilities_all.dart';

class UserSearchDialog extends StatefulWidget {
  final List<UserInfoModel> allUsers;
  const UserSearchDialog({super.key, required this.allUsers});

  @override
  State<UserSearchDialog> createState() => _UserSearchDialogState();
}

class _UserSearchDialogState extends State<UserSearchDialog> {
  late List<UserInfoModel> _filteredUsers;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredUsers = List.from(widget.allUsers);
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterUsers);
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = List.from(widget.allUsers);
      });
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      setState(() {
        _filteredUsers = widget.allUsers.where((user) {
          final normalizedName =
              Utilities.removeDiacritics(user.toFullNameString().toLowerCase());
          final normalizedEmail =
              Utilities.removeDiacritics((user.email ?? "").toLowerCase());

          return normalizedName.contains(normalizedQuery) ||
              normalizedEmail.contains(normalizedQuery);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(OrdersStrings.selectAttendee),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: OrdersStrings.searchPlaceholder,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  return ListTile(
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      user.toFullNameString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: user.email != null && user.email!.isNotEmpty
                        ? Text(user.email!)
                        : null,
                    onTap: () => Navigator.of(context).pop(user),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno), // Use CommonStrings
        ),
      ],
    );
  }
}
