/*	
	- Template Name: Jekas - Software,Studio And Corporate Template 
	- Autor: Iwthemes
	- Email: support@iwthemes.com
	- Name File: theme-options.js
	- Version 1.5 - Update on 9/09/2014
	- Website: http://www.iwthemes.com 
	- Copyright: (C) 2014
*/

$(document).ready(function($) {

	/* Selec your skin and layout Style */
	function interface(){

	    // Skin Version value
	    var skin_version = "style-light"; // style-light (default), style-dark 

	    // Skin Color value
	    var skin_color = "red"; // red (default), green , yellow , purple , blue , orange , purple , pink, cocoa , grey , custom 

	    // Boxed value
	    var layout = "layout-wide"; // layout-wide ( default) ,layout-boxed, layout-boxed-margin 

	    //Only in boxed version 
	    var bg = "none";  // none (default), bg1, bg2, bg3, bg4, bg5, bg6, bg7, bg8, bg9, bg10, bg11, bg12, bg13, 
	    				  // bg14, bg15, bg16, bg17, bg18, bg19,bg20, bg21, bg22, bg23, bg24, bg12, bg25, bg26

	    // Theme Panel - Visible - no visible panel options
	    var themepanel = "0"; // 1 (default - visible), 0 ( No visible)

	    $("#layout").addClass(skin_version);	
	    $(".skin_color").attr("href", "css/skins/"+ skin_color + "/" + skin_color + ".css");
	    $("#layout").addClass(layout);	
	    $("body").addClass(bg);   
	    $("#theme-options").css('opacity' , themepanel);
	    return false;
  	}
 	interface();

	//=================================== Theme Options ====================================//

	$('.wide').click(function() {
		$('.boxed').removeClass('active');
		$('.boxed-margin').removeClass('active');
		$(this).addClass('active');
		$('.patterns').css('display' , 'none');
		$('#layout').removeClass('layout-boxed').removeClass('layout-boxed-margin').addClass('layout-wide');
	});
	$('.boxed').click(function() {
		$('.wide').removeClass('active');
		$('.boxed-margin').removeClass('active');
		$(this).addClass('active');
		$('.patterns').css('display' , 'block');
		$('#layout').removeClass('layout-boxed-margin').removeClass('layout-wide').addClass('layout-boxed');
	});
	$('.boxed-margin').click(function() {
		$('.boxed').removeClass('active');
		$('.wide').removeClass('active');
		$(this).addClass('active');
		$('.patterns').css('display' , 'block');
		$('#layout').removeClass('layout-wide').removeClass('layout-boxed').addClass('layout-boxed-margin');
	});
	$('.light').click(function() {
		$('.dark').removeClass('active');
		$(this).addClass('active');
		$('#layout').removeClass('style-dark').addClass('style-light');
	});
	$('.dark').click(function() {
		$('.light').removeClass('active');
		$(this).addClass('active');
		$('#layout').removeClass('style-light').addClass('style-dark');
	});


    // Color changer
    $(".red").click(function(){
        $(".skin_color").attr("href", "css/skins/red/red.css");
        $(".logo_img").attr("src", "css/skins/red/logo.png");
        return false;
    });
    
    $(".blue").click(function(){
        $(".skin_color").attr("href", "css/skins/blue/blue.css");
        $(".logo_img").attr("src", "css/skins/blue/logo.png");
        return false;
    });
    
    $(".yellow").click(function(){
        $(".skin_color").attr("href", "css/skins/yellow/yellow.css");
        $(".logo_img").attr("src", "css/skins/yellow/logo.png");
        return false;
    });

    $(".green").click(function(){
        $(".skin_color").attr("href", "css/skins/green/green.css");
        $(".logo_img").attr("src", "css/skins/green/logo.png");
        return false;
    });

    $(".orange").click(function(){
        $(".skin_color").attr("href", "css/skins/orange/orange.css");
        $(".logo_img").attr("src", "css/skins/orange/logo.png");
        return false;
    });

    $(".purple").click(function(){
        $(".skin_color").attr("href", "css/skins/purple/purple.css");
        $(".logo_img").attr("src", "css/skins/purple/logo.png");
        return false;
    });

    $(".pink").click(function(){
        $(".skin_color").attr("href", "css/skins/pink/pink.css");
        $(".logo_img").attr("src", "css/skins/pink/logo.png");
        return false;
    });

    $(".cocoa").click(function(){
        $(".skin_color").attr("href", "css/skins/cocoa/cocoa.css");
        $(".logo_img").attr("src", "css/skins/cocoa/logo.png");
        return false;
    });

    $(".suelte").click(function(){
        $(".skin_color").attr("href", "css/skins/suelte/suelte.css");
        $(".logo_img").attr("src", "css/skins/suelte/logo.png");
        return false;
    });

    $(".grey").click(function(){
        $(".skin_color").attr("href", "css/skins/grey/grey.css");
        $(".logo_img").attr("src", "css/skins/grey/logo.png");
        return false;
    });

    $(".custom").click(function(){
        $(".skin_color").attr("href", "css/skins/custom/custom.css");
        $(".logo_img").attr("src", "css/skins/custom/logo.png");
        return false;
    });
	    

	//=================================== Background Options ====================================//
	
	$('#theme-options ul.backgrounds li').click(function(){
	var 	$bgSrc = $(this).css('background-image');
		if ($(this).attr('class') == 'bgnone')
			$bgSrc = "none";

		$('body').css('background-image',$bgSrc);
		$.cookie('background', $bgSrc);
		$.cookie('backgroundclass', $(this).attr('class').replace(' active',''));
		$(this).addClass('active').siblings().removeClass('active');
	});

	//=================================== Panel Options ====================================//

	$('.openclose').click(function(){
		if ($('#theme-options').css('left') == "-222px")
		{
			$left = "0px";
			$.cookie('displayoptions', "0");
		} else {
			$left = "-222px";
			$.cookie('displayoptions', "1");
		}
		$('#theme-options').animate({
			left: $left
		},{
			duration: 500			
		});

	});

	$(function(){
		$('#theme-options').fadeIn();
		$bgSrc = $.cookie('background');
		$('body').css('background-image',$bgSrc);

		if ($.cookie('displayoptions') == "1")
		{
			$('#theme-options').css('left','-222px');
		} else if ($.cookie('displayoptions') == "0") {
			$('#theme-options').css('left','0');
		} else {
			$('#theme-options').delay(800).animate({
				left: "-222px"
			},{
				duration: 500				
			});
			$.cookie('displayoptions', "1");
		}
		$('#theme-options ul.backgrounds').find('li.' + $.cookie('backgroundclass')).addClass('active');

	});

});