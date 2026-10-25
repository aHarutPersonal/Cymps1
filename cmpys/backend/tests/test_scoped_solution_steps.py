import copy
import pytest
from app.services.planning.lesson_package import LessonPackage,PrivatePackageRepair,apply_private_package_repair
from tests.test_lesson_pipeline_reliability import package_payload

@pytest.mark.parametrize('defect',['none','outside_scope','unknown','duplicate','overlap'])
def test_one_field_explanation_repair_preserves_all_other_bytes(defect):
 package=LessonPackage.model_validate(package_payload());a=package.workbook.activities[0];other=package.workbook.activities[1]
 field=a.fields[0].id
 patch={'activity_id':a.id,'field_id':field,'explanation':'A corrected explanation follows the supplied evidence, preserves its facts, and checks the stated limits.'}
 raw={'solution_step_patches':[patch]}
 if defect=='outside_scope':patch.update(activity_id=other.id,field_id=other.fields[0].id)
 if defect=='unknown':patch['field_id']='missing'
 if defect=='duplicate':raw['solution_step_patches'].append(copy.deepcopy(patch))
 if defect=='overlap':raw['solution_patches']=[{'activity_id':a.id,'worked_solution':a.worked_solution.model_dump()}]
 repair=PrivatePackageRepair.model_validate(raw)
 if defect!='none':
  with pytest.raises(ValueError):apply_private_package_repair(package,repair,repair_targets=[f'practice.{a.id}.{field}'])
 else:
  result=apply_private_package_repair(package,repair,repair_targets=[f'practice.{a.id}.{field}'])
  assert result.writer_context()==package.writer_context()
  expected=package.model_dump();expected['workbook']['activities'][0]['worked_solution']['steps'][0]['explanation']=patch['explanation']
  assert result.model_dump()==expected
