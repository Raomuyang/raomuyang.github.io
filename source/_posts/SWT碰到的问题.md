---
title: 关于在使用Java的SWT开发UI时UI总是发生卡死的情况及解决办法
date: 2016-08-09 17:40:12
tags: [Java,SWT]
meta: [Java,SWT开发UI时UI总是发生卡死的情况及解决办法]
categories: [Java]
---

> [问题描述]最近在尝试重构一个用SWT写的图形客户端，这个过程中遇到很多问题，其中最显著的就是SWT的客户端经常发生卡死。所谓成也萧何，败也萧何。避免UI失去响应的关键就在于下面这段代码

```java
while (!shell.isDisposed()) {
			if (!Display.getDefault().readAndDispatch()) {
				Display.getDefault().sleep();
			}
		}
```
<!--more-->
***以上这段代码的作用是，当在父面板打开一个新的子面板时，调用这段代码，可以将此操作后面的程序都阻塞，直到子面板被关闭才会继续执行后面的代码。在这种情况下，焦点在新打开的这个面板上，ui线程被阻塞，是无论如何不会失去响应的***

```java
public void open() {
        shell.open();
        shell.layout();
        while (!shell.isDisposed()) {
			if (!Display.getDefault().readAndDispatch()) {
				Display.getDefault().sleep();
			}
		}
}

public void operat(){
  open();//open以下的程序都被阻塞，shell被dispose才继续执行
  xxx();
  ...
  ...
}
```
因为SWT只有一个UI线程，Display在所有线程中为单例，若将阻塞线程的这段代码屏蔽掉，则又会碰到另一个新的问题：
> 如下代码所示：当open后面的操作为耗时和不耗时两种情况时，就会产生两种不同的结果
* 不耗时：程序执行完open操作后，不会阻塞后面的xxx操作，xxx操作会在后台继续执行
* 耗时：因为子面板被打开后又没用阻塞线程，在开始一段时间内后面的xxx操作继续在后台执行，但是当执行时间过长时，SWT子面板长时间未响应，就会被系统变成卡死的状态

```java
  public void open() {
          shell.open();
          shell.layout();
  		}
  }

  public void 非耗时(){
    open();
    xxx();
  }

  public void 耗时(){
    open();
    xxx();
    ...
    ...
  }
```

因为验证登录是一个耗时操作，所以我想在点击登录按钮时弹出一个dialog就碰到尴尬的问题了：
* 如果我阻塞线程，程序绝不会卡死，但是只有将dialog关闭后，才会继续执行后面的联网验证登录操作
* 如果我屏蔽阻塞线程的代码，网络状态良好的情况下，也不会发生卡死的状况，一旦网络状况不太好，程序就极容易失去响应

Eclipse在启动时的加载画面有时也会失去响应，该不会真的没有解决办法了吧。
> [问题解决] 毕竟SWT是个比较古老的东西，我只能试着看看能不能找到答案。我无意间发现jface中有一个`org.eclipse.jface.dialogs.ProgressMonitorDialog`，看起来很符合我们的需求

```java
    ProgressMonitorDialog progress = new ProgressMonitorDialog(getShell());
		progress.setCancelable(true);
		try {
				progress.run(true, true, new IRunnableWithProgress(){
              @Override
              public void run(IProgressMonitor arg0) throws InvocationTargetException, InterruptedException {
                  //耗时操作
                  doOperate();
              }
      });
		} catch (InvocationTargetException | InterruptedException e) {
				// TODO Auto-generated catch block
		}
```
在`ProcessMonitorDialog`的使用中，将耗时操作封装成了一个`IRunnableWithProcess`,在渲染出GUI之后，在后台执行我们想要执行的耗时操作。根据`ProcessMonitorDialog`设计的提示，那我们也可以很容易使用SWT根据我们的需求定制我们想要的dialog：

```java
public class ShowLoadingDialog{

	private Shell shell;
	private Label label;//登录弹出框的提示

	private String title;
	private String text;

	private Thread job ;
	/**
	 * Create the dialog.
	 * @param parentShell
	 */
	private ShowLoadingDialog(Shell shell, String title, String text) {
		this.shell = shell;
		label = new Label(shell, SWT.NONE);

		this.text = text;
		this.title = title;
	}

	public static ShowLoadingDialog getDialog(Shell parentShell, String title, String text){
		Shell shell = new Shell(parentShell, SWT.DIALOG_TRIM | SWT.APPLICATION_MODAL);
		return new ShowLoadingDialog(shell, title, text);
	}


	public void open() {
		setDialog();
        shell.open();
        shell.layout();
        while (!shell.isDisposed()) {
			if (!Display.getDefault().readAndDispatch()) {
				Display.getDefault().sleep();
			}
		}
    }

	public void close(){
        shell.dispose();

	}
  /**
  * 将耗时操作封装到Runnable中，作为参数传入
  */
	public void run(Runnable runnable){
		job = new Thread(runnable);

    //定义一个Thread，用于扫描耗时操作是否完成，如果已经完成，则关闭dialog
		Thread scan = new Thread(){
			public void run(){
				while(job.isAlive())
					if(shell.isDisposed())
						job.stop();//如果关闭，则停止job

				Display.getDefault().asyncExec(new Runnable() {
					@Override
					public void run() {
						// TODO Auto-generated method stub
						close();
					}
				});

			}
		};

		job.start();
		scan.start();
		open();
	}

  /**
  * 定义dialog的布局
  */
	protected void setDialog() {
		MacSetFullScreenUtil.setFullScreen(shell);

		Composite parent = shell.getParent();
		Point parentPoint = parent.getLocation();
		int parentW = parent.getSize().x;//parent.getBounds().width
		int parentH = parent.getSize().y;

		int shellW = 345;
		int shellH = 181;
		int locX = parentPoint.x + (parentW - shellW)/2;
		int locY = parentPoint.y + (parentH - shellH)/2;

        shell.setBounds(locX , locY, shellW, shellH);
        shell.setText(title);

        int labW = 204;
        int labH = 44;
        int labX = (shellW - labW)/2;
        int labY = (shellH - labH)/2;
        label.setAlignment(SWT.CENTER);
        label.setText(text);
        label.setBounds(labX, labY, labW, labH);
    }

	public Thread getJob(){return this.job;}


}
```
