// Code generated by "stringer -type Sushi sushi.go"; DO NOT EDIT

package sushi

import "fmt"

const _Sushi_name = "MaguroIkuraUniTamago"

var _Sushi_index = [...]uint8{0, 6, 11, 14, 20}

func (i Sushi) String() string {
	if i >= Sushi(len(_Sushi_index)-1) {
		return fmt.Sprintf("Sushi(%d)", i)
	}
	return _Sushi_name[_Sushi_index[i]:_Sushi_index[i+1]]
}
