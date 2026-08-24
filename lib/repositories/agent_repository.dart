import 'package:flutter/foundation.dart';
import '../models/agent.dart';
import '../services/database_service.dart';

class AgentRepository {
  const AgentRepository();

  Future<List<Agent>> getAll() async {
    try {
      return await DatabaseService.getAgents();
    } catch (e) {
      debugPrint('[AgentRepo] getAll error: $e');
      return [];
    }
  }

  Future<Agent?> getById(String id) async {
    try {
      return await DatabaseService.getAgent(id);
    } catch (e) {
      debugPrint('[AgentRepo] getById error: $e');
      return null;
    }
  }

  Future<void> insert(Agent agent) async {
    await DatabaseService.insertAgent(agent);
  }

  Future<void> update(Agent agent) async {
    await DatabaseService.updateAgent(agent);
  }

  Future<void> delete(String id) async {
    await DatabaseService.deleteAgent(id);
  }

  Future<void> setActive(String id) async {
    await DatabaseService.setActiveAgent(id);
  }
}
