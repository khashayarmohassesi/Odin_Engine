package main

import "core:fmt"
import "core:sys/windows"
//Todo Global for now
Running : bool
BitmapInfo : windows.BITMAPINFO
BitmapMemory : rawptr
BitmapHandle : windows.HBITMAP
BitmapDeviceContext : windows.HDC
@(private="file")
ResizeDIBSection :: proc "stdcall" ( Width: i32, Height: i32){
	//Todo: Bulletproof this
	//Maybe don't free first, free after, then free first if that fails

	if BitmapHandle != nil {
		windows.DeleteObject(windows.HGDIOBJ(BitmapHandle))
	}
	if BitmapDeviceContext == nil {
		//Todo: Should we recreate these under certain special circumstances
		BitmapDeviceContext = windows.CreateCompatibleDC(nil)
	}
	
	BitmapInfo.bmiHeader.biSize = size_of(BitmapInfo.bmiHeader)
	BitmapInfo.bmiHeader.biWidth = Width
	BitmapInfo.bmiHeader.biHeight = Height
	BitmapInfo.bmiHeader.biPlanes = 1
	BitmapInfo.bmiHeader.biBitCount = 32
	BitmapInfo.bmiHeader.biCompression = windows.BI_RGB
	BitmapInfo.bmiHeader.biSizeImage = 0
	BitmapInfo.bmiHeader.biXPelsPerMeter = 0
	BitmapInfo.bmiHeader.biYPelsPerMeter = 0
	BitmapInfo.bmiHeader.biClrImportant = 0

	
	BitmapHandle := windows.CreateDIBSection(
		BitmapDeviceContext,
		&BitmapInfo,
		windows.DIB_RGB_COLORS,
			&BitmapMemory,
		nil,0	)


}
@(private="file")
UpdateWindow :: proc "stdcall"(DeviceContext : windows.HDC,
							   X : i32,
							   Y : i32,
							   Width: i32,
							   Height: i32) {
	windows.StretchDIBits(DeviceContext,
						  X,
						  Y,
						  Width,
						  Height,
						  X,
						  Y,
						  Width,
						  Height,
						  BitmapMemory,
						  &BitmapInfo,
						  windows.DIB_RGB_COLORS,
						  windows.SRCCOPY)
}


MainWindowCallback :: proc "stdcall"(hwnd : windows.HWND ,
									 Message: u32,
									 WPARAM: uintptr ,
									 LPARAM: int ) -> int {
	
	Result : windows.LRESULT = 0
	
	switch Message {
	case windows.WM_SIZE : {//Create a buffer and draw a buffer
		ClientRect : windows.RECT
		//LPRect?
		windows.GetClientRect(hwnd,&ClientRect)
		Width := ClientRect.right - ClientRect.left
		Height := ClientRect.bottom - ClientRect.top
		ResizeDIBSection(Width, Height)
		windows.OutputDebugStringA("WM_Size")
	}
	case windows.WM_DESTROY : {
		//Todo: Handle this as an error - recreate window?
		Running = false
	}
	case windows.WM_CLOSE : {
		//Todo: Handle this with a message to the user
		Running = false
	}
	case windows.WM_ACTIVATEAPP : {
		windows.OutputDebugStringA("WM_ActivateApp")		
	}
	case windows.WM_PAINT: {
		Paint : windows.PAINTSTRUCT
		//HDC
		DeviceContext := windows.BeginPaint(hwnd, &Paint)
		
		X : i32 = Paint.rcPaint.left
		Y : i32 = Paint.rcPaint.top
		Width : i32 = Paint.rcPaint.right - Paint.rcPaint.left;
		Height : i32 = Paint.rcPaint.bottom - Paint.rcPaint.top
		UpdateWindow(DeviceContext,X,Y,Width,Height)
		
		windows.EndPaint(hwnd, &Paint)
	}
	case :{
		//		windows.OutputDebugStringA("default")
		Result = windows.DefWindowProcA(hwnd,Message,WPARAM,LPARAM)
	}
	}
	return Result
}

main :: proc(){

	
	
	wnd : windows.WNDCLASSW
	wnd.style = windows.CS_OWNDC | windows.CS_HREDRAW | windows.CS_VREDRAW
	wnd.lpfnWndProc = MainWindowCallback
	wnd.hInstance = windows.HINSTANCE( windows.GetModuleHandleW(""))
	//	wnd.hIcon = ;
	wnd.lpszClassName = "OdinEngine"

	//Returns an Atom but I don't care
	if windows.RegisterClassW(&wnd) != 0 {
		WindowHandle := windows.CreateWindowExW (
			0, 
			wnd.lpszClassName,
			"OdinEngine",
			windows.WS_OVERLAPPEDWINDOW | windows.WS_VISIBLE, 
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			nil,
			nil,
			wnd.hInstance,
			nil)
		if WindowHandle != nil {
			Running = true
			Message : windows.MSG
			//it seems there's no while loop in odin
			//it's all for loop, and I've dropped the increment step and the initial step
			for ; Running; {
				MessageResult : i32 = windows.GetMessageW(&Message,nil,0,0)
				
				if MessageResult > 0 {
					windows.TranslateMessage(&Message)
					windows.DispatchMessageW(&Message)
				}
				else { //if it returns 0 it has to close, if it's -1 the window has encountered an error
					break
				}

			}
			
		}
		else {
			//Todo: Window Handle Failed, Logging
		}
	}
	else {
		//Todo: register window class failed, Logging
	}
		
	return
}
