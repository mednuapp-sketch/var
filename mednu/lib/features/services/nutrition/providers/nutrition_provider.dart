import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nutritionist_model.dart';
import '../models/nutrition_appointment_model.dart';
import '../models/meal_log_model.dart';
import '../models/nutrition_goal_model.dart';
import '../models/diet_plan_model.dart';
import '../models/bmi_log_model.dart';
import '../services/nutrition_service.dart';

// ── Diet Plans ─────────────────────────────────────────

final dietPlansStreamProvider =
    StreamProvider.autoDispose<List<DietPlanModel>>((ref) {
  return NutritionService.dietPlansStream();
});

// ── Nutritionists ──────────────────────────────────────

final nutritionistSpecialtyFilterProvider = StateProvider<String?>((ref) => null);

final nutritionistsStreamProvider =
    StreamProvider.autoDispose<List<NutritionistModel>>((ref) {
  final specialty = ref.watch(nutritionistSpecialtyFilterProvider);
  return NutritionService.nutritionistsStream(specialty: specialty);
});

final nutritionistDetailProvider =
    StreamProvider.autoDispose.family<NutritionistModel?, String>((ref, id) {
  return NutritionService.nutritionistStream(id);
});

final bookedSlotsProvider =
    StreamProvider.autoDispose.family<List<String>, (String, String)>((ref, args) {
  return NutritionService.bookedSlotsStream(args.$1, args.$2);
});

// ── Appointments ───────────────────────────────────────

final nutritionAppointmentsProvider =
    StreamProvider.autoDispose<List<NutritionAppointmentModel>>((ref) {
  return NutritionService.userAppointmentsStream();
});

// ── Meal Tracking ──────────────────────────────────────

final selectedMealDateProvider = StateProvider<String?>((ref) => null);

final mealLogsProvider =
    StreamProvider.autoDispose<List<MealLogModel>>((ref) {
  final date = ref.watch(selectedMealDateProvider);
  return NutritionService.mealLogsStream(dateKey: date);
});

// Total calories for today
final todayCaloriesProvider = Provider.autoDispose<AsyncValue<double>>((ref) {
  return ref.watch(mealLogsProvider).whenData(
        (logs) => logs.fold<double>(0, (sum, log) => sum + log.calories),
      );
});

// ── Goals ──────────────────────────────────────────────

final activeNutritionGoalProvider =
    StreamProvider.autoDispose<NutritionGoalModel?>((ref) {
  return NutritionService.activeGoalStream();
});

// ── Water Tracking ──────────────────────────────────────

final waterGlassesProvider = StreamProvider.autoDispose<int>((ref) {
  return NutritionService.waterTrackingStream();
});

class WaterUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  WaterUpdateNotifier() : super(const AsyncData(null));

  Future<void> setGlasses(int glasses) async {
    state = const AsyncLoading();
    try {
      await NutritionService.updateWaterGlasses(glasses);
      state = const AsyncData(null);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }
}

final waterUpdateProvider =
    StateNotifierProvider.autoDispose<WaterUpdateNotifier, AsyncValue<void>>(
        (ref) => WaterUpdateNotifier());

// ── Booking State ──────────────────────────────────────

class BookingState {
  final bool isLoading;
  final String? error;
  final String? confirmedId;

  const BookingState({this.isLoading = false, this.error, this.confirmedId});

  BookingState copyWith({bool? isLoading, String? error, String? confirmedId}) =>
      BookingState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        confirmedId: confirmedId ?? this.confirmedId,
      );
}

class NutritionBookingNotifier extends StateNotifier<BookingState> {
  NutritionBookingNotifier() : super(const BookingState());

  Future<bool> bookAppointment({
    required String nutritionistId,
    required String nutritionistName,
    required String nutritionistSpecialization,
    required String consultationType,
    required String date,
    required String timeSlot,
    required String notes,
    required double fee,
    required String healthGoal,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final id = await NutritionService.bookAppointment(
        nutritionistId: nutritionistId,
        nutritionistName: nutritionistName,
        nutritionistSpecialization: nutritionistSpecialization,
        consultationType: consultationType,
        date: date,
        timeSlot: timeSlot,
        notes: notes,
        fee: fee,
        healthGoal: healthGoal,
      );
      state = state.copyWith(isLoading: false, confirmedId: id);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  void reset() => state = const BookingState();
}

final nutritionBookingProvider =
    StateNotifierProvider.autoDispose<NutritionBookingNotifier, BookingState>(
        (ref) => NutritionBookingNotifier());

// ── Meal Logging State ─────────────────────────────────

class MealLoggingNotifier extends StateNotifier<AsyncValue<void>> {
  MealLoggingNotifier() : super(const AsyncData(null));

  Future<bool> logMeal({
    required String mealType,
    required String foodName,
    required double calories,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    String notes = '',
  }) async {
    state = const AsyncLoading();
    try {
      await NutritionService.logMeal(
        mealType: mealType,
        foodName: foodName,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        notes: notes,
      );
      state = const AsyncData(null);
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  Future<void> deleteLog(String id) async {
    await NutritionService.deleteMealLog(id);
    state = const AsyncData(null);
  }
}

final mealLoggingProvider =
    StateNotifierProvider.autoDispose<MealLoggingNotifier, AsyncValue<void>>(
        (ref) => MealLoggingNotifier());

// ── BMI Tracking ────────────────────────────────────────

final bmiLogsProvider =
    StreamProvider.autoDispose<List<BmiLogModel>>((ref) {
  return NutritionService.bmiLogsStream();
});

class BmiSaveNotifier extends StateNotifier<AsyncValue<void>> {
  BmiSaveNotifier() : super(const AsyncData(null));

  Future<bool> save({
    required double heightCm,
    required double weightKg,
    required int age,
    required String gender,
    required double bmi,
    required String category,
  }) async {
    state = const AsyncLoading();
    try {
      await NutritionService.saveBmiLog(
        heightCm: heightCm,
        weightKg: weightKg,
        age: age,
        gender: gender,
        bmi: bmi,
        category: category,
      );
      state = const AsyncData(null);
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }
}

final bmiSaveProvider =
    StateNotifierProvider.autoDispose<BmiSaveNotifier, AsyncValue<void>>(
        (ref) => BmiSaveNotifier());
