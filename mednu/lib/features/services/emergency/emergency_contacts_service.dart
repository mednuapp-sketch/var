import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String phone;

  const EmergencyContact({required this.id, required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
      );
}

class EmergencyContactsService {
  static const _key = 'sos_emergency_contacts';

  static Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((e) => EmergencyContact.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  static Future<void> addContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    contacts.add(contact);
    await prefs.setStringList(_key, contacts.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> removeContact(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.id == id);
    await prefs.setStringList(_key, contacts.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> updateContact(EmergencyContact updated) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    final index = contacts.indexWhere((c) => c.id == updated.id);
    if (index != -1) contacts[index] = updated;
    await prefs.setStringList(_key, contacts.map((e) => jsonEncode(e.toJson())).toList());
  }
}
