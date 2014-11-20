/*	
	- Template Name: Jekas - Software,Studio And Corporate Template 
	- Autor: Iwthemes
	- Email: support@iwthemes.com
	- Name File: main.js
	- Version 1.5 - Update on 30/08/2014
	- Website: http://www.iwthemes.com 
	- Copyright: (C) 2014
*/

$(document).ready(function($) {

	'use strict';

	//=================================== Twitter Feed  ===============================//

    $(".twitts").tweet({
       modpath: 'js/twitter/index.php',
       username: "envato", // Change for Your Username
       count: 5,
       loading_text: "Loading tweets..."
    });

	//=================================== Nav Responsive ===============================//

	$('#menu').tinyNav({
	    active: 'selected'
	});

	//=================================== Sticky nav ===================================//

	// $(".nav_logo").sticky({topSpacing:0});

	//=================================== Nav Superfish ===============================//

	$('ul.sf-menu').superfish();

	//=================================== Nav Scroll ==================================//

	$('nav ul li a').click(function(){
        var el = $(this).attr('href');
        var elWrapped = $(el);  
        scrollToDiv(elWrapped,40);
        return false;    
    });

    function scrollToDiv(element,navheight){
	    var offset = element.offset();
	    var offsetTop = offset.top;
	    var totalScroll = offsetTop-navheight;
        $('body,html').animate({
                scrollTop: totalScroll
        }, 500);
    }

	//=================================== Totop  ===================================//

	$().UItoTop({ 		
		scrollSpeed:500,
		easingType:'linear'
	});	

	//=================================== Subtmit Form  =================================//

	$('#form').submit(function(event) {  
	  event.preventDefault();  
	  var url = $(this).attr('action');  
	  var datos = $(this).serialize();  
	  $.get(url, datos, function(resultado) {  
	    $('#result').html(resultado);  
	  });  
	});  

	//=================================== Subtmit Form Newslleter ===========================//

	$('#newsletterForm').submit(function(event) {  
	      event.preventDefault();  
	      var url = $(this).attr('action');
	      var datos = $(this).serialize();  
	       $.get(url, datos, function(resultado) {  
	        $('#result-newsletter').html(resultado);  
		});
	}); 

    //=================================== Accordion  =================================//
	
	$('.accordion-container').hide(); 
	$('.accordion-trigger:first').addClass('active').next().show();
	$('.accordion-trigger').click(function(){
		if( $(this).next().is(':hidden') ) { 
			$('.accordion-trigger').removeClass('active').next().slideUp();
			$(this).toggleClass('active').next().slideDown();
		}
		return false;
	});

	//=================================== Parallax Efect =====================================//
   
  	$('.bg_parallax').parallax("50%", .12);

	//=================================== Ligbox  ===================================//	

	$("a[class*=ligbox-image]").fancybox({
		overlayOpacity	:	0.7,
		overlayColor		:	'#000000',
		openEffect	: 'elastic',
    	closeEffect	: 'elastic',
		speedIn 			: '700',
		centerOnScroll	: true,
		helpers : {
    		title : {
    			type : 'inside'
    		}
    	}
	});

	$(".ligbox-various").fancybox({
		maxWidth	: 800,
		maxHeight	: 600,
		fitToView	: false,
		width		: '70%',
		height		: '70%',
		autoSize	: false,
		closeClick	: false,
		openEffect	: 'elastic',
    	closeEffect	: 'elastic',
		speedIn 			: '700',
		centerOnScroll	: true,
		helpers : {
    		title : {
    			type : 'inside'
    		}
    	}
	});
	
	//=============================  tooltip demo ===========================================//

    $('.tooltip-hover').tooltip({
        selector: "[data-toggle=tooltip]",
        container: "body"
    });
	

	//================================== Grid Gallery ====================================//

	$('#ri-grid').gridrotator({

		// number of rows
		rows : 2,

		// number of columns
		columns : 8,

		// rows/columns for different screen widths
		// i.e. w768 is for screens smaller than 768 pixels
		w1024 : {
			rows : 2,
			columns : 6
		},

		w768 : {
			rows : 2,
			columns : 5
		},

		w480 : {
			rows : 2,
			columns : 4
		},

		w320 : {
			rows : 2,
			columns : 3
		},

		w240 : {
			rows : 2,
			columns : 3
		},

		// step: number of items that are replaced at the same time
		// random || [some number]
		// note: for performance issues, the number should not be > options.maxStep
		step : 'random',
		maxStep : 3,

		// prevent user to click the items
		preventClick : true,

		// animation type
		// showHide || fadeInOut || slideLeft ||
		// slideRight || slideTop || slideBottom ||
		// rotateLeft || rotateRight || rotateTop ||
		// rotateBottom || scale || rotate3d ||
		// rotateLeftScale || rotateRightScale ||
		// rotateTopScale || rotateBottomScale || random
		animType : 'random',

		// animation speed
		animSpeed : 600,

		// animation easings
		animEasingOut : 'linear',
		animEasingIn : 'linear',

		// the item(s) will be replaced every 3 seconds
		// note: for performance issues, the time "can't" be < 300 ms
		interval : 2500,
		// if false the animations will not start
		// use false if onhover is true for example
		slideshow : true,
		// if true the items will switch when hovered
		onhover : false,
		// ids of elements that shouldn't change
		nochange : []

	});

	//=================================== Carousel team =====================================//

	$( '#mi-slider' ).catslider();


	//=================================== Carousel portfolio =====================================//

	$('#carousel-portfolio').owlCarousel({
	   	loop:true,
	    margin:20,
	    nav:false,
	    responsive:{
	        0:{
	            items:1
	        },
	        600:{
	            items:2
	        },
	        1000:{
	            items:3
	        },
	        1200:{
	            items:4
	        }
	    }
	})

	//=================================== Carousel Testimonials =====================================//

	$('#carousel-testimonials').owlCarousel({
	   	loop:true,
	    margin:0,
	    autoplay: true,
	    autoplayTimeout:3500,
	    nav:false,
	    items:1,
	    responsive:{
	        0:{
	            items:1
	        },
	        600:{
	            items:1
	        },
	        1000:{
	            items:1
	        }
	    }
	})

	//=================================== Carousel Testimonials =====================================//

	$('#carousel-sponsors').owlCarousel({
	   	loop:true,
	    margin:0,
	    autoplay: true,
	    autoplayTimeout:3500,
	    nav:false,
	    items:6,
	    responsive:{
	        0:{
	            items:3
	        },
	        600:{
	            items:4
	        },
	        1000:{
	            items:6
	        }
	    }
	})

	//=================================== Carousel Testimonials =====================================//

	$('#carousel-team-members').owlCarousel({
	   	loop:true,
	    margin:30,
	    autoplay: true,
	    autoplayTimeout:3500,
	    nav:false,
	    items:4,
	    responsive:{
	        0:{
	            items:2
	        },
	        600:{
	            items:3
	        },
	        1000:{
	            items:4
	        }
	    }
	})

	//=================================== Carousel Single =====================================//

	$('#carousel-single').owlCarousel({
	   	loop:true,
	    margin:0,
	    autoplay: true,
	    autoplayTimeout:3500,
	    nav:false,
	    items:1,
	    responsive:{
	        0:{
	            items:1
	        },
	        600:{
	            items:1
	        },
	        1000:{
	            items:1
	        }
	    }
	})

	//=================================== Carousel Twitter =====================================//

	$('.tweet_list').owlCarousel({
	   	loop:true,
	    margin:0,
	    autoplay: true,
	    autoplayTimeout:3500,
	    nav:false,
	    items:1,
	    responsive:{
	        0:{
	            items:1
	        },
	        600:{
	            items:1
	        },
	        1000:{
	            items:1
	        }
	    }
	})

	//=================================== Portfolio Filters  ==============================//

		$(window).load(function(){
	     var $container = $('.portfolioContainer');
	     $container.isotope({
	      filter: '*',
	              animationOptions: {
	              duration: 750,
	              easing: 'linear',
	              queue: false
	            }
	     });
		 
	    $('.portfolioFilter a').click(function(){
	      $('.portfolioFilter .current').removeClass('current');
	      $(this).addClass('current');
	       var selector = $(this).attr('data-filter');
	       $container.isotope({
	        filter: selector,
	               animationOptions: {
	               duration: 750,
	               easing: 'linear',
	               queue: false
	             }
	        });
	       return false;
	      }); 
	});

	//================================ Animations Efect ===================================//
	
	new WOW().init();

});