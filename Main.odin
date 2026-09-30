package main

import "core:fmt"
import "core:sys/windows"
import "core:mem"
//Todo Global for now
Running : bool
BitmapInfo : windows.BITMAPINFO
BitmapMemory : rawptr
BitmapWidth : i32
BitmapHeight : i32
BytesPerPixel : i32 = 4
@(private="file")
RenderWeirdGradient :: proc "stdcall" (XOffset : i32, YOffset : i32) {
	Width := BitmapWidth
	Height := BitmapHeight
	
	Pitch := Width *BytesPerPixel

	//casting from rawptr to char pointer
	//leaving this comment here to make myself remember the odin syntax
	Row : ^u8 = cast (^u8) BitmapMemory
		
	for Y : i32= 0; Y < BitmapHeight; Y+=1 {
		//I'm so not sure about this
		//I'm trying to cast the Row PTR to a u32 PTR
		//I'm casting it first and then taking the pointer of it and THEN dereferencing with ^?
		Pixel : ^u32 = &(cast(^u32) Row)^
			
		for X: i32 = 0; X< BitmapWidth; X+=1 {
			Blue : u8 =cast(u8) (X + XOffset)
			Green : u8 =cast(u8) (Y + YOffset)
			Pixel^ = cast(u32) (cast(u32)Green <<8) | cast(u32) Blue
			//ptr offset takes the size of the ptr being passed into it
			//I thought I should pass 4 into it, but 1 works here
			//just like ptr++; in C that would move the pointer 4 bytes if it was an int
			
			Pixel = mem.ptr_offset(Pixel,1)
		}
		Row = mem.ptr_offset(Row,Pitch)
	}
}

@(private="file")
ResizeDIBSection :: proc "stdcall" ( Width: i32, Height: i32){
	//Todo: Bulletproof this
	//Maybe don't free first, free after, then free first if that fails
	if BitmapMemory != nil {
		windows.VirtualFree(BitmapMemory, 0, windows.MEM_RELEASE)
	}
	BitmapWidth = Width
	BitmapHeight = Height
	BitmapInfo.bmiHeader.biSize = size_of(BitmapInfo.bmiHeader)
	BitmapInfo.bmiHeader.biWidth = BitmapWidth
	BitmapInfo.bmiHeader.biHeight = -BitmapHeight
	BitmapInfo.bmiHeader.biPlanes = 1
	BitmapInfo.bmiHeader.biBitCount = 32
	BitmapInfo.bmiHeader.biCompression = windows.BI_RGB
	BitmapInfo.bmiHeader.biSizeImage = 0
	BitmapInfo.bmiHeader.biXPelsPerMeter = 0
	BitmapInfo.bmiHeader.biYPelsPerMeter = 0
	BitmapInfo.bmiHeader.biClrImportant = 0

	BitmapMemorySize : i32 =  (Width* Height)*BytesPerPixel
	BitmapMemory = windows.VirtualAlloc(nil, uint (BitmapMemorySize),windows.MEM_COMMIT,windows.PAGE_READWRITE)

	RenderWeirdGradient(128,0)

}
@(private="file")
UpdateWindow :: proc "stdcall"(DeviceContext : windows.HDC,
							   ClientRect : ^windows.RECT,
							   X : i32,
							   Y : i32,
							   Width: i32,
							   Height: i32) {
	
	WindowWidth := ClientRect.right - ClientRect.left
	WindowHeight := ClientRect.bottom - ClientRect.top
	windows.StretchDIBits(DeviceContext,
	//					  X,
	//					  Y,
		//				  Width,
		//				  Height,
		//				  X,
		//				  Y,
		//				  Width,
						  //				  Height,
						  0,0, BitmapWidth,BitmapHeight,
						  0,0, WindowWidth,WindowHeight,
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

		ClientRect : windows.RECT
		windows.GetClientRect(hwnd,&ClientRect)
		
		Width : i32 = Paint.rcPaint.right - Paint.rcPaint.left;
		Height : i32 = Paint.rcPaint.bottom - Paint.rcPaint.top
		UpdateWindow(DeviceContext,&ClientRect,X,Y,Width,Height)
		
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
			XOffset : i32 = 0
			YOffset : i32 = 0
			//it seems there's no while loop in odin
			//it's all for loop, and I've dropped the increment step and the initial step
			for ; Running; {

				MessageResult : b32 = cast(b32) windows.PeekMessageW(&Message,nil,0,0, windows.PM_REMOVE)
				for MessageResult == false  {
					if Message.message == windows.WM_QUIT {
						Running = false
					}
					windows.TranslateMessage(&Message)
					windows.DispatchMessageW(&Message)
				}
				RenderWeirdGradient(XOffset,YOffset)
				
				{
					DeviceContext : windows.HDC = windows.GetDC(WindowHandle )
					ClientRect : windows.RECT
					windows.GetClientRect(WindowHandle,&ClientRect)
					WindowWidth : i32 = ClientRect.right - ClientRect.left
					WindowHeight : i32 = ClientRect.bottom - ClientRect.top
					UpdateWindow(DeviceContext,&ClientRect,0,0,WindowWidth,WindowHeight)
					windows.ReleaseDC(WindowHandle,DeviceContext)
				}
				
				XOffset +=1
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
