import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'ownership_details_repository.dart';
import 'ownership_details_state.dart';

class OwnershipDetailsCubit extends Cubit<OwnershipDetailsState> {
  final OwnershipDetailsRepository repository;

  OwnershipDetailsCubit(this.repository) : super(OwnershipDetailsInitial());

  Future<void> getRenterDetails(String id) async {
    emit(OwnershipDetailsLoading());
    try {
      final renter = await repository.getRenterDetails(id);
      log('Renter details fetched successfully: $renter');
      emit(OwnershipDetailsSuccess(renter));
    } catch (e) {
      log('Error fetching renter details: ${e.toString()}');
      emit(OwnershipDetailsError(e.toString()));
    }
  }
}
