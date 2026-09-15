class_name TestSuite
extends RefCounted
## TestSuite —— 无头测试套件基类。
##
## 新增测试：在 tests/suites/ 下建脚本 `extends TestSuite`，
## 实现 suite_name() 与 run(t)，再把脚本加进 tests/test_main.gd 的 SUITES 数组。
## run(t) 里的 t 是 TestMain 节点，提供 check / eq / near 断言方法。


## 套件显示名
func suite_name() -> String:
	return "unnamed"


## 测试主体
func run(_t: Node) -> void:
	pass
