#pragma once

// subclass a dialog Edit control so pressing enter enters data not goes bong

class SUBCLASSWIN {
public:
	// frig is used to find the internal EDIT control in a COMBOBOX
	SUBCLASSWIN(HWND hwnd, HWND htarget, bool frig=false){
		if(frig){
			POINT pt{3,3};
			hwnd = ChildWindowFromPoint(hwnd, pt);
		}
		hOld = hwnd;
		hTarget = htarget;
		SetWindowLongPtr(hwnd, GWLP_USERDATA, (LPARAM)this);
		oldProc = (WNDPROC)SetWindowLongPtr(hwnd, GWLP_WNDPROC, (LONG_PTR)proc);
	}
	~SUBCLASSWIN(){
		SetWindowLongPtr(hOld, GWLP_WNDPROC, (LONG_PTR)oldProc);
	}
private:
	HWND hOld;
	HWND hTarget;
	WNDPROC oldProc;

	static LRESULT CALLBACK proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam){
		SUBCLASSWIN *me = (SUBCLASSWIN*)GetWindowLongPtr(hwnd, GWLP_USERDATA);
		if(msg==WM_KEYDOWN && wParam==VK_RETURN){
			SendMessage(me->hTarget, msg, wParam, lParam);
			return 0;
		}
		else if(msg==WM_CHAR && wParam==VK_RETURN){
			SendMessage(me->hTarget, msg, wParam, lParam);
			return 0;
		}
		return (*me->oldProc)(hwnd, msg, wParam, lParam);
	}
};
