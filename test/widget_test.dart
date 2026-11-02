import 'package:flutter_test/flutter_test.dart';
import 'package:purpose_money/format.dart';
import 'package:purpose_money/models.dart';

void main() {
  test('family model reads budgets and approvals', () {
    final f = Family('fam1', {
      'name': 'Okonkwo Family',
      'siblingUids': ['a', 'b', 'c'],
      'parentUids': ['m'],
      'memberNames': {'a': 'Chidi'},
      'rules': {'siblingApprovalsRequired': 2},
      'purposes': {
        'school': {'label': 'School fees', 'budgetNgn': 120000, 'spentNgn': 0},
        'food': {'label': 'Food', 'budgetNgn': 100000, 'spentNgn': 130000},
      },
    });
    expect(f.purposes.first.key, 'food');
    expect(f.purpose('food')!.remainingNgn, 0);
    expect(f.purpose('food')!.progress, 1.0);
    expect(f.approvalsNeeded, 2);
    expect(f.nameOf('a'), 'Chidi');
    expect(f.nameOf('zz'), 'Family member');
  });

  test('formatting', () {
    expect(naira(45000), '₦45,000');
    expect(initial(' ada'), 'A');
  });
}
