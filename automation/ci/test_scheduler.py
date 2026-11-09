import threading
import unittest
from scheduler import execute_dag


class SchedulerTest(unittest.TestCase):
    def test_shared_claims_bound_workers_and_dependencies_run_after_success(self):
        lock=threading.Lock();active=0;peak=0;finished=[]
        def execute(name,unit):
            nonlocal active,peak
            with lock:active+=1;peak=max(peak,active)
            if name=='after':self.assertIn('first',finished)
            with lock:active-=1;finished.append(name)
        units={'first':{'resources':{'flutter':1}},'second':{'resources':{'flutter':1}},'after':{'after':['first'],'resources':{'flutter':1}}}
        result=execute_dag(units,{'flutter':1},execute)
        self.assertEqual(peak,1);self.assertTrue(all(row['status']=='PASS' for row in result.values()))

    def test_isolated_database_units_overlap_but_cluster_mutations_remain_exclusive(self):
        together=threading.Barrier(2)
        lock=threading.Lock()
        active=0
        peak=0
        def execute(name,unit):
            nonlocal active,peak
            if name=='cluster-mutation':
                with lock: self.assertEqual(active,0)
                return
            with lock:
                active+=1
                peak=max(peak,active)
            try: together.wait(timeout=5)
            finally:
                with lock: active-=1
        units={
            'isolated-a':{'resources':{'dbCluster':1}},
            'isolated-b':{'resources':{'dbCluster':1}},
            'cluster-mutation':{'resources':{'dbCluster':2}},
        }
        result=execute_dag(units,{'dbCluster':2},execute,workers=3)
        self.assertEqual(peak,2)
        self.assertTrue(all(row['status']=='PASS' for row in result.values()),result)

    def test_failed_dependency_cannot_be_success_and_independent_work_finishes(self):
        executed=[]
        def execute(name,unit):
            executed.append(name)
            if name=='bad':raise RuntimeError('fixture failed')
        result=execute_dag({'bad':{},'blocked':{'after':['bad']},'independent':{}},{},execute)
        self.assertEqual(result['blocked']['status'],'INCOMPLETE')
        self.assertNotIn('blocked',executed);self.assertEqual(result['independent']['status'],'PASS')

    def test_cycles_unknown_dependencies_and_excess_claims_are_rejected(self):
        for units in [{'a':{'after':['b']},'b':{'after':['a']}},{'a':{'after':['unknown']}},{'a':{'resources':{'ram':2}}}]:
            with self.assertRaises(ValueError):execute_dag(units,{'ram':1},lambda *_:None)


if __name__=='__main__':unittest.main()
