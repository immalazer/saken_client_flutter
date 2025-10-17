import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:saken/model/song_model.dart';

class ApiClient {
  String host = 'localhost';
  String apiPort = "8000";
  String get apiUrl => "http://$host:$apiPort/api";

  ApiClient();

  void setApiHost(String host) {
    this.host = host;
  }

  void updateSongMetadata(
    String filename,
    String title,
    String artist,
    String album,
  ) async {
    try {
      Map<String, String> requests = {};

      requests['title'] = title;
      requests['artist'] = artist;
      requests['album'] = album;

      sendPostRequest("songs/$filename", requests);
    } catch (e) {
      // Something terrible has happened.
    }
  }

  Future<Song?> getSong(String filename) async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/songs/$filename"));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body)[0] as Map<String, dynamic>;
        return Song.fromJson(json);
      } else {
        return null;
      }
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
    return null;
  }

  Future<List<Song>> fetchSongs() async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/songs"));

      if (response.statusCode == 200) {
        List<dynamic> json = jsonDecode(response.body);
        return json.map((data) => Song.fromJson(data)).toList();
      } else {
        throw Exception('Failed to load song');
      }
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
    return List.empty();
  }

  Future<MemoryImage?> getAlbumArt(String filename) async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/art/$filename"));

      if (response.statusCode == 200) {
        return MemoryImage(response.bodyBytes);
      } else {
        return null;
      }
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
    return null;
  }

  Future<void> uploadSong() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: false,
      withReadStream: true,
    );

    if (result?.files.first != null) {
      final file = result!.files.first;

      try {
        var postUri = Uri.parse("$apiUrl/songs");
        var request = http.MultipartRequest("POST", postUri);

        request.files.add(
          http.MultipartFile(
            'file',
            http.ByteStream(file.readStream!),
            file.size,
            filename: "file", // Won't be read, but we need this somehow.
          ),
        );

        await request.send();
      } catch (e) {
        // Something really terrible has happened, and we shouldn't ignore it.
      }
    } else {
      // User canceled the picker
    }
  }

  Future<void> deleteSong(String filename) async {
    try {
      var postUri = Uri.parse("$apiUrl/songs/$filename");
      var request = http.MultipartRequest("DELETE", postUri);
      await request.send();
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
  }

  Future<dynamic> sendPostRequest(
    String apiPath,
    Map<String, String> requests,
  ) async {
    try {
      var postUri = Uri.parse("$apiUrl/$apiPath");
      var request = http.MultipartRequest("POST", postUri);

      requests.forEach((key, value) {
        request.fields[key] = value;
      });

      await request.send();
    } catch (e) {
      // Something terrible has happened.
    }
  }
}
